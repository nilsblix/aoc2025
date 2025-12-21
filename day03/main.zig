const std = @import("std");

const Battery = struct {
    idx: usize,
    value: usize,
};

fn totalJoltage(reader: *std.Io.Reader) !usize {
    var sum: usize = 0;

    while (true) {
        const bank = try reader.takeDelimiter('\n') orelse break;
        if (bank.len == 0) continue;

        var fst = Battery{ .idx = 0, .value = 0 };

        for (0..bank.len - 1) |idx| {
            const value = try std.fmt.parseInt(usize, bank[idx .. idx + 1], 10);
            if (value > fst.value) {
                fst.value = value;
                fst.idx = idx;
            }
        }

        var snd = Battery{ .idx = fst.idx + 1, .value = 0 };
        for (fst.idx + 1..bank.len) |idx| {
            const value = try std.fmt.parseInt(usize, bank[idx .. idx + 1], 10);
            if (value > snd.value) {
                snd.value = value;
                snd.idx = idx;
            }
        }

        std.debug.assert(fst.value < 10);
        std.debug.assert(snd.value < 10);
        std.debug.assert(fst.idx != snd.idx);

        if (fst.idx < snd.idx) {
            sum += fst.value * 10 + snd.value;
        } else {
            sum += snd.value * 10 + fst.value;
        }
    }

    return sum;
}

fn overrideJoltage(reader: *std.Io.Reader, comptime n: usize) !usize {
    var sum: usize = 0;

    while (true) {
        const bank = try reader.takeDelimiter('\n') orelse break;
        if (bank.len == 0) continue;

        std.debug.assert(bank.len >= n);

        var batteries: [n]Battery = undefined;
        inline for (0..n) |i| {
            batteries[i] = .{
                .idx = 0,
                .value = 0,
            };
        }

        inline for (0..n) |i| {
            var b = &batteries[i];
            const start_idx = if (i == 0) 0 else batteries[i - 1].idx + 1;
            const last_idx = bank.len - n + i + 1;

            for (start_idx..last_idx) |j| {
                const value = try std.fmt.parseInt(usize, bank[j .. j + 1], 10);
                if (value > b.value) {
                    b.value = value;
                    b.idx = j;
                }
            }
        }

        inline for (0..n) |i| {
            const b = batteries[i];
            std.debug.assert(b.value < 10);

            const j = i + 1;
            sum += b.value * std.math.pow(usize, 10, n - j);
        }
    }

    return sum;
}

test "example part 1" {
    var file = try std.fs.cwd().openFile("day03/input-test.txt", .{});
    defer file.close();
    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const sum = try totalJoltage(&reader.interface);
    try std.testing.expect(sum == 357);
}

test "final part 1" {
    var file = try std.fs.cwd().openFile("day03/input.txt", .{});
    defer file.close();
    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const sum = try totalJoltage(&reader.interface);
    try std.testing.expect(sum == 17095);
}

test "example part 2" {
    var file = try std.fs.cwd().openFile("day03/input-test.txt", .{});
    defer file.close();
    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const sum = try overrideJoltage(&reader.interface, 12);
    try std.testing.expect(sum == 3121910778619);
}

test "final part 2" {
    var file = try std.fs.cwd().openFile("day03/input.txt", .{});
    defer file.close();
    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const sum = try overrideJoltage(&reader.interface, 12);
    try std.testing.expect(sum == 168794698570517);
}

pub fn main() !void {
    var file = try std.fs.cwd().openFile("day03/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const sum = try overrideJoltage(&reader.interface, 12);

    std.debug.print("{d}\n", .{sum});
}
