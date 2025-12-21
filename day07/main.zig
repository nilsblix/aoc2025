const std = @import("std");

pub fn splits(reader: *std.fs.File.Reader) !usize {
    const tach_start = try reader.interface.discardDelimiterInclusive('S');
    const tach_until_end = try reader.interface.discardDelimiterExclusive('\n');

    const line_len = tach_start + tach_until_end;

    const max_line_len: usize = 1024;
    std.debug.assert(max_line_len > line_len);

    var tachs = std.bit_set.IntegerBitSet(max_line_len).initEmpty();
    tachs.set(tach_start);

    var s: usize = 0;
    var idx: usize = 0;
    while (true) {
        const b = reader.interface.takeByte() catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };

        switch (b) {
            '\n' => idx = 0,
            '.' => idx += 1,
            '^' => {
                idx += 1;
                if (tachs.isSet(idx)) {
                    s += 1;
                    tachs.unset(idx);
                    if (idx > 0) {
                        tachs.set(idx - 1);
                    }
                    if (idx < line_len - 1) {
                        tachs.set(idx + 1);
                    }
                }
            },
            else => unreachable,
        }
    }

    return s;
}

pub fn timelines(reader: *std.fs.File.Reader) !usize {
    const tach_start = try reader.interface.discardDelimiterInclusive('S');
    const tach_until_end = try reader.interface.discardDelimiterExclusive('\n');

    const line_len = tach_start + tach_until_end;

    const bit_set_size: usize = 1024;
    std.debug.assert(bit_set_size > line_len);

    const max_line_len: usize = 1024;
    var tachs_buf: [max_line_len]u64 = @splat(0);
    var tachs = tachs_buf[0..line_len];

    tachs[tach_start] += 1;

    var t: usize = 1;
    var idx: usize = 0;
    while (true) {
        const b = reader.interface.takeByte() catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };

        switch (b) {
            '\n' => idx = 0,
            '.' => idx += 1,
            '^' => {
                idx += 1;
                t += tachs[idx];
                if (tachs[idx] > 0) {
                    if (idx > 0) {
                        tachs[idx - 1] += tachs[idx];
                    }
                    if (idx < line_len - 1) {
                        tachs[idx + 1] += tachs[idx];
                    }
                    tachs[idx] = 0;
                }
            },
            else => unreachable,
        }
    }

    return t;
}

test "example part 1" {
    var f = try std.fs.cwd().openFile("day07/input-test.txt", .{});
    defer f.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = f.reader(&reader_buf);

    const n = try splits(&reader);
    try std.testing.expect(n == 21);
}

test "final part 1" {
    var f = try std.fs.cwd().openFile("day07/input.txt", .{});
    defer f.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = f.reader(&reader_buf);

    const n = try splits(&reader);
    try std.testing.expect(n == 1585);
}

test "example part 2" {
    var f = try std.fs.cwd().openFile("day07/input-test.txt", .{});
    defer f.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = f.reader(&reader_buf);

    const n = try timelines(&reader);
    try std.testing.expect(n == 40);
}

test "final part 2" {
    var f = try std.fs.cwd().openFile("day07/input.txt", .{});
    defer f.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = f.reader(&reader_buf);

    const n = try timelines(&reader);
    try std.testing.expect(n == 16716444407407);
}

pub fn main() !void {
    var f = try std.fs.cwd().openFile("day07/input.txt", .{});
    defer f.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = f.reader(&reader_buf);

    const n = try timelines(&reader);
    std.debug.print("{d}\n", .{n});
}
