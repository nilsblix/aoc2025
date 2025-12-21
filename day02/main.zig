const std = @import("std");
const Allocator = std.mem.Allocator;

fn isInvalid(id: []const u8) bool {
    if (id.len % 2 != 0) return false;

    const fst = id[0 .. id.len / 2];
    const snd = id[id.len / 2 ..];
    return std.mem.eql(u8, fst, snd);
}

fn isInvalidPart2(id: []const u8) bool {
    const n = id.len;

    for (1..(n / 2) + 1) |i| {
        var s = id;

        // If the tried repetition's length doesn't divide the total length
        // then this cannot be a repetition.
        if (@mod(n, i) != 0) continue;

        const head = id[0..i];
        while (true) {
            if (s.len == 0) return true;

            const starts_with = std.mem.startsWith(u8, s, head);
            if (!starts_with) break;

            s = s[i..];
        }
    }

    return false;
}

fn parseTrimmedInt(comptime T: type, s: []const u8, base: u8) !T {
    const trimmed = std.mem.trim(u8, s, " \r\n\t");
    return std.fmt.parseInt(T, trimmed, base);
}

fn sumInvalids(alloc: Allocator, reader: *std.Io.Reader, comptime part2: bool) !u64 {
    var acc: u64 = 0;

    while (true) {
        const range = try reader.takeDelimiter(',') orelse break;
        var it = std.mem.splitAny(u8, range[0..], "-");

        const fst_slice = it.next() orelse return error.WrongFormat;
        const snd_slice = it.next() orelse return error.WrongFormat;

        const fst = try parseTrimmedInt(u64, fst_slice, 10);
        const snd = try parseTrimmedInt(u64, snd_slice, 10);

        for (fst..snd + 1) |id| {
            const id_str = try std.fmt.allocPrint(alloc, "{d}", .{id});
            defer alloc.free(id_str);

            const isInv = if (part2) isInvalidPart2 else isInvalid;

            if (isInv(id_str)) {
                acc += id;
            }
        }
    }

    return acc;
}

test "example part1" {
    var file = try std.fs.cwd().openFile("day02/input-test.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);
    const sum = try sumInvalids(std.heap.page_allocator, &reader.interface, false);
    try std.testing.expect(sum == 1227775554);
}

test "final part1" {
    var file = try std.fs.cwd().openFile("day02/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);
    const sum = try sumInvalids(std.heap.page_allocator, &reader.interface, false);
    try std.testing.expect(sum == 21139440284);
}

test "example part2" {
    var file = try std.fs.cwd().openFile("day02/input-test.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);
    const sum = try sumInvalids(std.heap.page_allocator, &reader.interface, true);
    try std.testing.expect(sum == 4174379265);
}

test "final part2" {
    var file = try std.fs.cwd().openFile("day02/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);
    const sum = try sumInvalids(std.heap.page_allocator, &reader.interface, true);
    try std.testing.expect(sum == 38731915928);
}

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer {
    //     const res = gpa.deinit();
    //     if (res == .leak) {
    //         std.log.err("Leak detected", .{});
    //     }
    // }
    // const alloc = gpa.allocator();
    const alloc = std.heap.page_allocator;

    var file = try std.fs.cwd().openFile("day02/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const sum = try sumInvalids(alloc, &reader.interface, true);
    std.debug.print("sum = {d}\n", .{sum});
}
