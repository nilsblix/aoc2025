const std = @import("std");
const Allocator = std.mem.Allocator;

test "split on several blankspaces" {
    var it = std.mem.tokenizeAny(u8, "hello world  double   triple", " ");
    try std.testing.expect(std.mem.eql(u8, it.next().?, "hello"));
    try std.testing.expect(std.mem.eql(u8, it.next().?, "world"));
    try std.testing.expect(std.mem.eql(u8, it.next().?, "double"));
    try std.testing.expect(std.mem.eql(u8, it.next().?, "triple"));
}

const Row = struct {
    iter: std.mem.TokenIterator(u8, .any),
    buf: []u8,
};

fn grand(alloc: Allocator, reader: *std.Io.Reader) !u64 {
    var rows = try std.ArrayList(Row).initCapacity(alloc, 0);
    defer {
        for (rows.items) |r| {
            alloc.free(r.buf);
        }
        rows.deinit(alloc);
    }

    while (true) {
        const line = try reader.takeDelimiter('\n') orelse break;

        const buf = try alloc.dupe(u8, line);
        const iter = std.mem.tokenizeAny(u8, buf, " ");
        const row = Row{
            .iter = iter,
            .buf = buf,
        };

        try rows.append(alloc, row);
    }

    var g: u64 = 0;
    while (true) {
        var op_iter = &rows.items[rows.items.len - 1].iter;
        const op_slice = op_iter.next() orelse break;

        std.debug.assert(op_slice.len == 1);
        const op = op_slice[0];

        var local: u64 = grand: switch (op) {
            '+' => break :grand 0,
            '*' => break :grand 1,
            else => return error.UnhandledOperation,
        };

        for (rows.items[0..rows.items.len - 1]) |*n_row| {
            const n_slice = n_row.iter.next() orelse return error.ImpossibleSituation;
            const n = try std.fmt.parseInt(u64, n_slice, 10);

            switch (op) {
                '+' => local += n,
                '*' => local *= n,
                else => return error.UnhandledOperation,
            }
        }

        g += local;
    }

    return g;
}

test "example part 1" {
    var file = try std.fs.cwd().openFile("day6/input-test.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const n = try grand(std.heap.page_allocator, &reader.interface);
    try std.testing.expect(n == 4277556);
}

test "final part 1" {
    var file = try std.fs.cwd().openFile("day6/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const n = try grand(std.heap.page_allocator, &reader.interface);
    try std.testing.expect(n == 4693419406682);
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

    var file = try std.fs.cwd().openFile("day6/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const g = try grand(alloc, &reader.interface);
    std.debug.print("{d}\n", .{g});
}
