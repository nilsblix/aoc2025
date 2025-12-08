const std = @import("std");
const Allocator = std.mem.Allocator;

// Idea:
// The input data is formatted as follows:
// ```
// |
// |
// some ranges
// |
// |
//
// |
// ids to check
// |
// ```
// We want to normalize the ranges; which means sorting them based on start and
// then eliminating all overlaps. We could then do a simple binary search on
// each `id to check` which should be faster than simple brute force.

/// Both are inclusive.
const Range = struct {
    start: usize,
    end: usize,
};

fn normalizeRanges(alloc: Allocator, ranges: []const Range) ![]Range {
    if (ranges.len == 0) {
        // Either return an empty dup or just an empty slice literal if caller
        // doesn't need ownership:
        return alloc.dupe(Range, ranges);
    }

    var tmp = try alloc.dupe(Range, ranges);

    std.mem.sort(Range, tmp, {}, struct {
        fn lessThan(_: void, lhs: Range, rhs: Range) bool {
            if (lhs.start == rhs.start) return lhs.end < rhs.end;
            return lhs.start < rhs.start;
        }
    }.lessThan);

    var out_len: usize = 1;
    for (tmp[1..]) |r| {
        var last = &tmp[out_len - 1];
        // We are garuanteed that r.start >= last.start.
        std.debug.assert(r.start >= last.start);

        if (r.start <= last.end) {
            // r overlaps with the last range; extend last if needed.
            if (r.end > last.end) last.end = r.end;
        } else {
            // Non-overlapping range: place it immediately after the last merged
            // range to keep the merged slice compact.
            tmp[out_len] = r;
            out_len += 1;
        }
    }

    return tmp[0..out_len];
}

fn isFresh(id: usize, normalized: []const Range) bool {
    var lo: usize = 0;
    var hi: usize = normalized.len;

    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const r = normalized[mid];

        if (id < r.start) {
            hi = mid;
        } else if (id > r.end) {
            lo = mid + 1;
        } else {
            return true;
        }
    }
    return false;
}

fn freshIngredients(alloc: Allocator, reader: *std.Io.Reader, total: bool) !usize {
    var unsorted = try std.ArrayList(Range).initCapacity(alloc, 0);
    defer unsorted.deinit(alloc);

    while (true) {
        const line = try reader.takeDelimiter('\n') orelse break;

        if (line.len == 0) {
            // We know that this line is the empty/separating line. Currently,
            // we simply break out.
            break;
        }

        var it = std.mem.splitAny(u8, line[0..], "-");
        const start_slice = it.next() orelse return error.UnhandledFormat;
        const end_slice = it.next() orelse return error.UnhandledFormat;

        std.debug.assert(it.next() == null);

        const range = Range{
            .start = try std.fmt.parseInt(usize, start_slice, 10),
            .end = try std.fmt.parseInt(usize, end_slice, 10),
        };

        try unsorted.append(alloc, range);
    }

    var normalized = try normalizeRanges(alloc, unsorted.items[0..]);
    defer {
        normalized.len = unsorted.items.len;
        alloc.free(normalized);
    }

    if (!total) {
        var num_fresh: usize = 0;
        while (true) {
            const line = try reader.takeDelimiter('\n') orelse break;
            const id = try std.fmt.parseInt(usize, line, 10);
            if (isFresh(id, normalized)) {
                num_fresh += 1;
            }
        }
        return num_fresh;
    }

    // We want to know the total amount of fresh ingredients, i.e the total span
    // of all ranges.
    var n: usize = 0;
    for (normalized) |r| {
        n += 1 + r.end - r.start;
    }
    return n;
}

test "example part 1" {
    var file = try std.fs.cwd().openFile("day5/input-test.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const n = try freshIngredients(std.heap.page_allocator, &reader.interface, false);
    try std.testing.expect(n == 3);
}

test "final part 1" {
    var file = try std.fs.cwd().openFile("day5/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const n = try freshIngredients(std.heap.page_allocator, &reader.interface, false);
    try std.testing.expect(n == 720);
}

test "example part 2" {
    var file = try std.fs.cwd().openFile("day5/input-test.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const n = try freshIngredients(std.heap.page_allocator, &reader.interface, true);
    try std.testing.expect(n == 14);
}

test "final part 2" {
    var file = try std.fs.cwd().openFile("day5/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const n = try freshIngredients(std.heap.page_allocator, &reader.interface, true);
    try std.testing.expect(n == 357608232770687);
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

    var file = try std.fs.cwd().openFile("day5/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const num_fresh = try freshIngredients(alloc, &reader.interface, true);
    std.debug.print("{d}\n", .{num_fresh});
}
