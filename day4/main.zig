const std = @import("std");
const Allocator = std.mem.Allocator;

const offsets: [8]struct { isize, isize } = .{
    .{ -1, -1 },
    .{  0, -1 },
    .{  1, -1 },
    .{ -1,  0 },
    .{  1,  0 },
    .{ -1,  1 },
    .{  0,  1 },
    .{  1,  1 },
};

fn accessiblesAssumeCapacity(chars: *const [][]u8, output_buf: ?*std.ArrayList(struct { usize, usize })) error{BufTooSmall}!usize {
    var count: usize = 0;

    for (chars.*, 0..) |row, i| {
        for_char: for (row, 0..) |char, j| {
            if (char != '@') continue;

            var filled: usize = 0;

            for (offsets) |offset| {
                const i_prime: usize = blk: {
                    if (offset.@"1" < 0 and i == 0) continue;
                    if (offset.@"1" > 0 and i == chars.len - 1) continue;

                    const i_prime: isize = @intCast(i);
                    break :blk @intCast(i_prime + offset.@"1");
                };

                const j_prime: usize = blk: {
                    if (offset.@"0" < 0 and j == 0) continue;
                    if (offset.@"0" > 0 and j == row.len - 1) continue;

                    const j_prime: isize = @intCast(j);
                    break :blk @intCast(j_prime + offset.@"0");
                };

                if (chars.*[i_prime][j_prime] == '@') {
                    filled += 1;
                }

                if (filled >= 4) {
                    continue :for_char;
                }
            }

            std.debug.assert(filled <= 3);

            if (output_buf) |out| {
                if (count > out.capacity) return error.BufTooSmall;
                out.appendAssumeCapacity(.{ i, j });
            }

            count += 1;
        }
    }

    return count;
}

fn numAccessibleRolls(alloc: Allocator, reader: *std.Io.Reader) !usize {
    var rolls = try std.ArrayList([]u8).initCapacity(alloc, 0);
    defer {
        for (rolls.items) |row| {
            alloc.free(row);
        }
        rolls.deinit(alloc);
    }

    while (true) {
        const row = try reader.takeDelimiter('\n') orelse break;
        const owned_row = try alloc.dupe(u8, row);
        try rolls.append(alloc, owned_row);
    }

    return accessiblesAssumeCapacity(@constCast(&rolls.items), null);
}

// Stroke of genius when naming this...
fn numForktruckable(alloc: Allocator, reader: *std.Io.Reader) !usize {
    var rolls = try std.ArrayList([]u8).initCapacity(alloc, 0);
    defer {
        for (rolls.items) |row| {
            alloc.free(row);
        }
        rolls.deinit(alloc);
    }

    while (true) {
        const row = try reader.takeDelimiter('\n') orelse break;
        const owned_row = try alloc.dupe(u8, row);
        try rolls.append(alloc, owned_row);
    }

    // FIXME: Is this even garuanteed to work? I don't thing so. There should
    // be a scenario in which removing some rolls frees up enough space to
    // create more accessible rolls.
    const n_max = try accessiblesAssumeCapacity(@constCast(&rolls.items), null);

    var accessible = try std.ArrayList(struct { usize, usize }).initCapacity(alloc, n_max);
    defer accessible.deinit(alloc);

    // How do I keep coming up with these impeccable names?
    var num_forked: usize = 0;
    while (true) {
        const n_free = try accessiblesAssumeCapacity(@constCast(&rolls.items), &accessible);
        if (n_free == 0) break;

        num_forked += n_free;

        for (accessible.items[0..n_free]) |pos| {
            // This is how we reset/truck away the roll.
            rolls.items[pos.@"0"][pos.@"1"] = '.';
        }

        accessible.clearRetainingCapacity();
    }

    return num_forked;
}

test "example part 1" {
    var file = try std.fs.cwd().openFile("day4/input-test.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const sum = try numAccessibleRolls(std.heap.page_allocator, &reader.interface);
    try std.testing.expect(sum == 13);
}

test "final part 1" {
    var file = try std.fs.cwd().openFile("day4/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const sum = try numAccessibleRolls(std.heap.page_allocator, &reader.interface);
    try std.testing.expect(sum == 1604);
}

test "example part 2" {
    var file = try std.fs.cwd().openFile("day4/input-test.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const sum = try numForktruckable(std.heap.page_allocator, &reader.interface);
    try std.testing.expect(sum == 43);
}

test "final part 2" {
    var file = try std.fs.cwd().openFile("day4/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const sum = try numForktruckable(std.heap.page_allocator, &reader.interface);
    try std.testing.expect(sum == 9397);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const res = gpa.deinit();
        if (res == .leak) {
            std.log.err("Leak detected", .{});
        }
    }
    const alloc = gpa.allocator();

    var file = try std.fs.cwd().openFile("day4/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const n = try numForktruckable(alloc, &reader.interface);
    std.debug.print("{d}\n", .{n});
}
