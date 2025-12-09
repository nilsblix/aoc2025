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

        for (rows.items[0 .. rows.items.len - 1]) |*n_row| {
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

const Block = struct {
    items: [][]const u8,

    fn calculateNumber(self: Block, col: usize) !u64 {
        const len = self.items.len;

        var num: u64 = 0;
        var pow: u64 = 0;
        var row: isize = @intCast(len - 2);
        // Traverse upwards from the operator-row, and increment pow if we are on a number.
        while (row >= 0) {
            defer row -= 1;

            const r = self.items[@intCast(row)];
            const char = r[col];
            if (char == ' ') {
                continue;
            }

            var val = try std.fmt.parseInt(u64, r[col .. col + 1], 10);
            std.debug.assert(1 <= val and val <= 9);
            val *= std.math.pow(u64, 10, pow);

            num += val;
            pow += 1;
        }

        return num;
    }

    fn calculate(self: Block) !u64 {
        const len = self.items.len;
        var op_it = std.mem.tokenizeAny(u8, self.items[len - 1], " ");
        const op_slice = op_it.next() orelse return error.NoOperatorFound;
        std.debug.assert(op_it.next() == null);
        std.debug.assert(op_slice.len == 1);
        const op = op_slice[0];

        var local: u64 = grand: switch (op) {
            '+' => break :grand 0,
            '*' => break :grand 1,
            else => return error.UnhandledOperation,
        };

        // We know since an earlier assert that all rows have the same length,
        // and that row 0 exists.
        const columns = self.items[0].len;
        for (0..columns) |col| {
            const n = try self.calculateNumber(col);
            switch (op) {
                '+' => local += n,
                '*' => local *= n,
                else => return error.UnhandledOperation,
            }
        }

        return local;
    }
};

fn parseBlocks(alloc: Allocator, rows: [][]u8) !std.ArrayList(Block) {
    // Each block stores [][]const u8, which is an array of slices that point
    // to some row in `rows`. `rows` owns all of its own memory, which means
    // that as long as `blocks` doesn't outlive `rows` we should be fine.
    //
    // We do not free these. The function caller needs to free these.
    var blocks = try std.ArrayList(Block).initCapacity(alloc, 0);

    const len = rows[0].len;
    const separator: u8 = ' ';

    // We assume that the start of the file is a block.
    var start_col: usize = 0;
    col: for (0..len) |col| {
        // We only check for this current column's separators if we are not at
        // the end.
        var c = col;
        if (c == len - 1) {
            // Here we are at the end, which means that we want to always
            // capture this block, and slice to the end.
            c = len;
        } else {
            for (rows) |r| {
                if (r[c] != separator) {
                    continue :col;
                }
            }
        }

        // Here we are on a column with all separators.
        var slices = try std.ArrayList([]const u8).initCapacity(alloc, 0);
        defer slices.deinit(alloc);
        for (rows) |r| {
            try slices.append(alloc, r[start_col..c]);
        }

        try blocks.append(alloc, .{
            .items = try alloc.dupe([]const u8, slices.items),
        });
        start_col = col + 1;
    }

    return blocks;
}

fn grandVerticalNumbers(alloc: Allocator, reader: *std.Io.Reader) !u64 {
    // Idea:
    // Instead of trying to calculate each block on the fly, we store a list of
    // blocks (which are one calculation each). A block is a part of the data
    // which is surrounded by spaces on all rows with the same column, ex:
    //  248
    //  953
    //  265
    //  *
    // ^   ^

    var rows = try std.ArrayList([]u8).initCapacity(alloc, 0);
    defer {
        for (rows.items) |r| {
            alloc.free(r);
        }
        rows.deinit(alloc);
    }

    while (true) {
        const row = try reader.takeDelimiter('\n') orelse break;
        const dup = try alloc.dupe(u8, row);
        try rows.append(alloc, dup);
    }

    // We need at least 3 lines to perform some sort of operation.
    std.debug.assert(rows.items.len >= 3);
    // Check that all rows have the same length.
    std.debug.assert(ok: {
        const l = rows.items[0].len;
        for (rows.items) |r| {
            if (r.len != l) break :ok false;
        }
        break :ok true;
    });

    var blocks = try parseBlocks(alloc, rows.items);
    defer {
        for (blocks.items) |bl| {
            alloc.free(bl.items);
        }
        blocks.deinit(alloc);
    }

    var sum: u64 = 0;
    for (blocks.items) |bl| {
        sum += try bl.calculate();
    }

    return sum;
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

test "example part 2" {
    var file = try std.fs.cwd().openFile("day6/input-test.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const n = try grandVerticalNumbers(std.heap.page_allocator, &reader.interface);
    try std.testing.expect(n == 3263827);
}

test "final part 2" {
    var file = try std.fs.cwd().openFile("day6/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const n = try grandVerticalNumbers(std.heap.page_allocator, &reader.interface);
    try std.testing.expect(n == 9029931401920);
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

    const g = try grandVerticalNumbers(alloc, &reader.interface);
    std.debug.print("{d}\n", .{g});
}
