const std = @import("std");
const Allocator = std.mem.Allocator;

fn maxRed(reader: *std.fs.File.Reader) !usize {
    var best_area: usize = 0;

    while (true) {
        // The input is formatted as follows:
        // col,row
        // col,row
        // ...
        const c1_slice = try reader.interface.takeDelimiter(',') orelse break;
        const r1_slice = try reader.interface.takeDelimiter('\n') orelse break;

        const next = reader.logicalPos();
        defer reader.seekTo(next) catch unreachable;

        const c1 = try std.fmt.parseInt(isize, c1_slice, 10);
        const r1 = try std.fmt.parseInt(isize, r1_slice, 10);

        while (true) {
            const c2_slice = try reader.interface.takeDelimiter(',') orelse break;
            const r2_slice = try reader.interface.takeDelimiter('\n') orelse break;

            const c2 = try std.fmt.parseInt(isize, c2_slice, 10);
            const r2 = try std.fmt.parseInt(isize, r2_slice, 10);

            if (c1 == c2 and r1 == r2) continue;

            const dx = @abs(c1 - c2);
            const dy = @abs(r1 - r2);

            const area: usize = @intCast((dx + 1) * (dy + 1));
            best_area = @max(best_area, area);
        }
    }

    return best_area;
}

fn getDims(reader: *std.fs.File.Reader) !Point {
    var width: usize = 0;
    var height: usize = 0;

    const start = reader.logicalPos();
    while (true) {
        const c_slice = try reader.interface.takeDelimiter(',') orelse break;
        const r_slice = try reader.interface.takeDelimiter('\n') orelse break;

        const c = try std.fmt.parseInt(usize, c_slice, 10);
        const r = try std.fmt.parseInt(usize, r_slice, 10);

        if (c > width) width = c;
        if (r > height) height = r;
    }

    try reader.seekTo(start);

    return .{ .col = width + 1, .row = height + 1 };
}

const Point = struct {
    col: usize,
    row: usize,

    fn eql(a: Point, b: Point) bool {
        return a.col == b.col and a.row == b.row;
    }
};

const Edge = struct {
    const Kind = enum { vertical, horizontal };

    p1: Point,
    p2: Point,
    kind: Kind,
};

const Filter = union(enum) {
    row: usize,
    col: usize,
};

/// Will return an owned slice with all edges that are perpendicular to the filter.
fn filterEdges(alloc: Allocator, edges: *const std.AutoArrayHashMap(Edge, void), f: Filter) ![]const Edge {
    var out = try std.ArrayList(Edge).initCapacity(alloc, 0);

    var it = edges.iterator();
    while (it.next()) |entry| {
        const e = entry.key_ptr.*;

        switch (f) {
            .row => |r| {
                if (e.kind == .horizontal) continue;

                const min = @min(e.p1.row, e.p2.row);
                const max = @max(e.p1.row, e.p2.row);
                if (min <= r and r < max) {
                    try out.append(alloc, e);
                }
            },
            .col => |c| {
                if (e.kind == .vertical) continue;

                const min = @min(e.p1.col, e.p2.col);
                const max = @max(e.p1.col, e.p2.col);
                if (min <= c and c < max) {
                    try out.append(alloc, e);
                }
            },
        }
    }

    return try out.toOwnedSlice(alloc);
}

const FilterCache = struct {
    allocator: Allocator,
    rows: std.AutoArrayHashMap(usize, []const Edge),
    cols: std.AutoArrayHashMap(usize, []const Edge),

    fn init(alloc: Allocator) FilterCache {
        return .{
            .allocator = alloc,
            .rows = std.AutoArrayHashMap(usize, []const Edge).init(alloc),
            .cols = std.AutoArrayHashMap(usize, []const Edge).init(alloc),
        };
    }

    fn deinit(self: *FilterCache) void {
        var rit = self.rows.iterator();
        while (rit.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.rows.deinit();

        var cit = self.cols.iterator();
        while (cit.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.cols.deinit();
    }

    fn row(self: *FilterCache, edges: *const std.AutoArrayHashMap(Edge, void), r: usize) ![]const Edge {
        if (self.rows.getPtr(r)) |ptr| return ptr.*;
        const filtered = try filterEdges(self.allocator, edges, .{ .row = r });
        try self.rows.put(r, filtered);
        return filtered;
    }

    fn col(self: *FilterCache, edges: *const std.AutoArrayHashMap(Edge, void), c: usize) ![]const Edge {
        if (self.cols.getPtr(c)) |ptr| return ptr.*;
        const filtered = try filterEdges(self.allocator, edges, .{ .col = c });
        try self.cols.put(c, filtered);
        return filtered;
    }
};

fn populateEdgesOrdered(
    edges: *std.AutoArrayHashMap(Edge, void),
    red_order: []const Point,
) !void {
    if (red_order.len == 0) return;

    for (red_order, 0..) |p, idx| {
        const next = red_order[(idx + 1) % red_order.len];
        std.debug.assert(p.row == next.row or p.col == next.col);

        const kind: Edge.Kind = if (p.row == next.row) .horizontal else .vertical;
        _ = try edges.getOrPut(.{ .p1 = p, .p2 = next, .kind = kind });
    }
}

fn isInside(p: Point, perp_edges: []const Edge, swipe: Edge.Kind) bool {
    if (perp_edges.len == 0) return false;

    var right_count: usize = 0;

    for (perp_edges) |perp| {
        std.debug.assert(perp.kind != swipe);
        switch (swipe) {
            .horizontal => std.debug.assert(perp.p1.col == perp.p2.col),
            .vertical => std.debug.assert(perp.p1.row == perp.p2.row),
        }

        const inc_right = switch (swipe) {
            .horizontal => perp.p1.col > p.col,
            .vertical => perp.p1.row > p.row,
        };

        if (inc_right) {
            right_count += 1;
        }
    }

    return @mod(right_count, 2) == 1;
}

fn onPolygonEdge(p: Point, edges: *const std.AutoArrayHashMap(Edge, void)) bool {
    var it = edges.iterator();
    while (it.next()) |entry| {
        const e = entry.key_ptr.*;
        switch (e.kind) {
            .vertical => {
                const min = @min(e.p1.row, e.p2.row);
                const max = @max(e.p1.row, e.p2.row);
                if (p.col == e.p1.col and min <= p.row and p.row <= max) return true;
            },
            .horizontal => {
                const min = @min(e.p1.col, e.p2.col);
                const max = @max(e.p1.col, e.p2.col);
                if (p.row == e.p1.row and min <= p.col and p.col <= max) return true;
            },
        }
    }

    return false;
}

fn validRectangle(
    edges: *const std.AutoArrayHashMap(Edge, void),
    cache: *FilterCache,
    p1: Point,
    p2: Point,
) !bool {
    const t1 = Point{ .col = @min(p1.col, p2.col), .row = @min(p1.row, p2.row) };
    const t2 = Point{ .col = @max(p1.col, p2.col), .row = @max(p1.row, p2.row) };

    const upper_perp = try cache.row(edges, t1.row);
    for (upper_perp) |perp| {
        if (perp.p1.col > t1.col and perp.p1.col < t2.col) return false;
    }
    const sample_top = Point{ .col = (t1.col + t2.col) / 2, .row = t1.row };
    if (!onPolygonEdge(sample_top, edges) and !isInside(sample_top, upper_perp, .horizontal)) return false;

    const lower_perp = try cache.row(edges, t2.row);
    for (lower_perp) |perp| {
        if (perp.p1.col > t1.col and perp.p1.col < t2.col) return false;
    }
    const sample_bottom = Point{ .col = (t1.col + t2.col) / 2, .row = t2.row };
    if (!onPolygonEdge(sample_bottom, edges) and !isInside(sample_bottom, lower_perp, .horizontal)) return false;

    const left_perp = try cache.col(edges, t1.col);
    for (left_perp) |perp| {
        if (perp.p1.row > t1.row and perp.p1.row < t2.row) return false;
    }
    const sample_left = Point{ .col = t1.col, .row = (t1.row + t2.row) / 2 };
    if (!onPolygonEdge(sample_left, edges) and !isInside(sample_left, left_perp, .vertical)) return false;

    const right_perp = try cache.col(edges, t2.col);
    for (right_perp) |perp| {
        if (perp.p1.row > t1.row and perp.p1.row < t2.row) return false;
    }
    const sample_right = Point{ .col = t2.col, .row = (t1.row + t2.row) / 2 };
    if (!onPolygonEdge(sample_right, edges) and !isInside(sample_right, right_perp, .vertical)) return false;

    return true;
}

const Candidate = struct { p1: Point, p2: Point, area: usize };

fn maxRedAndGreen(alloc: Allocator, reader: *std.fs.File.Reader) !usize {
    var reds = std.AutoArrayHashMap(Point, void).init(alloc);
    defer reds.deinit();

    var red_order = try std.ArrayList(Point).initCapacity(alloc, 0);
    defer red_order.deinit(alloc);

    while (true) {
        const c_slice = try reader.interface.takeDelimiter(',') orelse break;
        const r_slice = try reader.interface.takeDelimiter('\n') orelse break;

        const c = try std.fmt.parseInt(usize, c_slice, 10);
        const r = try std.fmt.parseInt(usize, r_slice, 10);

        const p = Point{ .col = c, .row = r };
        try reds.put(p, {});
        try red_order.append(alloc, p);
    }

    var edges = std.AutoArrayHashMap(Edge, void).init(alloc);
    defer edges.deinit();

    try populateEdgesOrdered(&edges, red_order.items);

    var cache = FilterCache.init(alloc);
    defer cache.deinit();
    var candidates = try std.ArrayList(Candidate).initCapacity(alloc, 0);
    defer candidates.deinit(alloc);

    for (red_order.items, 0..) |p1, i| {
        for (red_order.items[(i + 1)..]) |p2| {
            const dx = @abs(@as(isize, @intCast(p1.col)) - @as(isize, @intCast(p2.col)));
            const dy = @abs(@as(isize, @intCast(p1.row)) - @as(isize, @intCast(p2.row)));
            const area: usize = @intCast((dx + 1) * (dy + 1));

            try candidates.append(alloc, .{ .p1 = p1, .p2 = p2, .area = area });
        }
    }

    if (candidates.items.len == 0) return 0;

    std.sort.heap(Candidate, candidates.items, {}, struct {
        fn lessThan(_: void, a: Candidate, b: Candidate) bool {
            return a.area > b.area;
        }
    }.lessThan);

    for (candidates.items) |cand| {
        if (try validRectangle(@constCast(&edges), &cache, cand.p1, cand.p2)) return cand.area;
    }

    return 0;
}

test "example part 1" {
    var f = try std.fs.cwd().openFile("day09/input-test.txt", .{});
    defer f.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = f.reader(&reader_buf);

    const n = try maxRed(&reader);
    try std.testing.expect(n == 50);
}

test "final part 1" {
    var f = try std.fs.cwd().openFile("day09/input.txt", .{});
    defer f.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = f.reader(&reader_buf);

    const n = try maxRed(&reader);
    try std.testing.expect(n == 4749672288);
}

test "example part 2" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var f = try std.fs.cwd().openFile("day09/input-test.txt", .{});
    defer f.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = f.reader(&reader_buf);

    const n = try maxRedAndGreen(alloc, &reader);
    try std.testing.expect(n == 24);
}

test "final part 2" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var f = try std.fs.cwd().openFile("day09/input.txt", .{});
    defer f.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = f.reader(&reader_buf);

    const n = try maxRedAndGreen(alloc, &reader);
    try std.testing.expect(n == 1479665889);
}

test "isInside simple square" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const square = [_]Point{
        .{ .col = 0, .row = 0 },
        .{ .col = 2, .row = 0 },
        .{ .col = 2, .row = 2 },
        .{ .col = 0, .row = 2 },
    };

    var edges = std.AutoArrayHashMap(Edge, void).init(alloc);
    defer edges.deinit();
    try populateEdgesOrdered(&edges, &square);

    const verticals = try filterEdges(alloc, &edges, .{ .row = 1 });
    defer alloc.free(verticals);
    const horizontals = try filterEdges(alloc, &edges, .{ .col = 1 });
    defer alloc.free(horizontals);

    try std.testing.expect(isInside(.{ .col = 1, .row = 1 }, verticals, .horizontal));
    try std.testing.expect(!isInside(.{ .col = 3, .row = 1 }, verticals, .horizontal));
    try std.testing.expect(isInside(.{ .col = 1, .row = 1 }, horizontals, .vertical));
    try std.testing.expect(!isInside(.{ .col = 1, .row = 3 }, horizontals, .vertical));
}

test "validRectangle respects polygon bounds" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const square = [_]Point{
        .{ .col = 0, .row = 0 },
        .{ .col = 2, .row = 0 },
        .{ .col = 2, .row = 2 },
        .{ .col = 0, .row = 2 },
    };

    var edges = std.AutoArrayHashMap(Edge, void).init(alloc);
    defer edges.deinit();
    try populateEdgesOrdered(&edges, &square);

    var cache = FilterCache.init(alloc);
    defer cache.deinit();

    try std.testing.expect(try validRectangle(&edges, &cache, square[0], square[2]));
    try std.testing.expect(!try validRectangle(&edges, &cache, square[0], .{ .col = 3, .row = 2 }));
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

    var f = try std.fs.cwd().openFile("day09/input.txt", .{});
    defer f.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = f.reader(&reader_buf);

    const n = try maxRedAndGreen(alloc, &reader);
    std.debug.print("{d}\n", .{n});
}
