const std = @import("std");

const Point = struct { x: i32, y: i32, z: i32 };

// The puzzle input has 1000 points; keep a little headroom.
const max_points: usize = 1024;

const Pair = struct {
    a: usize,
    b: usize,
    dist2: i64,
};

fn parsePoint(line: []const u8) !Point {
    var it = std.mem.tokenizeScalar(u8, line, ',');
    const x = try std.fmt.parseInt(i32, it.next() orelse return error.BadLine, 10);
    const y = try std.fmt.parseInt(i32, it.next() orelse return error.BadLine, 10);
    const z = try std.fmt.parseInt(i32, it.next() orelse return error.BadLine, 10);
    if (it.next() != null) return error.BadLine;
    return .{ .x = x, .y = y, .z = z };
}

fn loadPoints(path: []const u8, buf: []Point) ![]Point {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = file.reader(&reader_buf);

    var idx: usize = 0;
    while (true) {
        if (idx == buf.len) return error.TooManyPoints;
        const line = try reader.interface.takeDelimiter('\n') orelse break;
        if (line.len == 0) continue;
        buf[idx] = try parsePoint(line);
        idx += 1;
    }
    return buf[0..idx];
}

fn distSquared(a: Point, b: Point) i64 {
    const dx: i64 = @as(i64, a.x) - @as(i64, b.x);
    const dy: i64 = @as(i64, a.y) - @as(i64, b.y);
    const dz: i64 = @as(i64, a.z) - @as(i64, b.z);
    return dx * dx + dy * dy + dz * dz;
}

fn buildSortedPairs(points: []const Point, allocator: std.mem.Allocator) ![]Pair {
    const n = points.len;
    const total_pairs = n * (n - 1) / 2;
    var pairs = try allocator.alloc(Pair, total_pairs);
    errdefer allocator.free(pairs);

    var idx: usize = 0;
    for (points, 0..) |a, i| {
        var j = i + 1;
        while (j < n) : (j += 1) {
            pairs[idx] = .{
                .a = i,
                .b = j,
                .dist2 = distSquared(a, points[j]),
            };
            idx += 1;
        }
    }

    std.mem.sort(Pair, pairs, {}, struct {
        fn lessThan(_: void, lhs: Pair, rhs: Pair) bool {
            return lhs.dist2 < rhs.dist2;
        }
    }.lessThan);

    std.debug.assert(idx == total_pairs);
    return pairs;
}

const DisjointSet = struct {
    parent: [max_points]usize = undefined,
    size: [max_points]usize = undefined,
    n: usize,

    fn init(n: usize) DisjointSet {
        var ds = DisjointSet{ .n = n };
        for (0..n) |i| {
            ds.parent[i] = i;
            ds.size[i] = 1;
        }
        return ds;
    }

    fn find(self: *DisjointSet, x: usize) usize {
        var v = x;
        while (self.parent[v] != v) {
            self.parent[v] = self.parent[self.parent[v]];
            v = self.parent[v];
        }
        return v;
    }

    fn unite(self: *DisjointSet, a: usize, b: usize) bool {
        var ra = self.find(a);
        var rb = self.find(b);
        if (ra == rb) return false;

        if (self.size[ra] < self.size[rb]) {
            const tmp = ra;
            ra = rb;
            rb = tmp;
        }
        self.parent[rb] = ra;
        self.size[ra] += self.size[rb];
        return true;
    }

    fn componentSizes(self: *DisjointSet, out: []usize) usize {
        @memset(out, 0);
        for (0..self.n) |i| {
            const root = self.find(i);
            out[root] += 1;
        }

        var count: usize = 0;
        for (0..self.n) |i| {
            const sz = out[i];
            if (sz != 0) {
                out[count] = sz;
                count += 1;
            }
        }
        return count;
    }
};

pub fn circuitProduct(path: []const u8, comptime num_shortest: usize) !usize {
    var point_buf: [max_points]Point = undefined;
    const points = try loadPoints(path, &point_buf);
    const n = points.len;
    if (n < 3) return error.NotEnoughPoints;

    const allocator = std.heap.page_allocator;
    const pairs = try buildSortedPairs(points, allocator);
    defer allocator.free(pairs);

    const use_pairs = @min(num_shortest, pairs.len);
    var ds = DisjointSet.init(n);
    for (pairs[0..use_pairs]) |p| {
        _ = ds.unite(p.a, p.b);
    }

    var size_buf: [max_points]usize = undefined;
    const size_count = ds.componentSizes(size_buf[0..n]);
    if (size_count < 3) return error.NotEnoughCircuits;
    const sizes = size_buf[0..size_count];
    std.mem.sort(usize, sizes, {}, struct {
        fn greaterThan(_: void, lhs: usize, rhs: usize) bool {
            return lhs > rhs;
        }
    }.greaterThan);

    return sizes[0] * sizes[1] * sizes[2];
}

pub fn lastConnectionXProduct(path: []const u8) !i64 {
    var point_buf: [max_points]Point = undefined;
    const points = try loadPoints(path, &point_buf);
    const n = points.len;
    if (n < 2) return error.NotEnoughPoints;

    const allocator = std.heap.page_allocator;
    const pairs = try buildSortedPairs(points, allocator);
    defer allocator.free(pairs);

    var ds = DisjointSet.init(n);
    var components = n;
    for (pairs) |p| {
        if (ds.unite(p.a, p.b)) {
            components -= 1;
            if (components == 1) {
                const xa: i64 = @as(i64, points[p.a].x);
                const xb: i64 = @as(i64, points[p.b].x);
                return xa * xb;
            }
        }
    }
    return error.NotFullyConnected;
}

test "example part 1" {
    const n = try circuitProduct("day8/input-test.txt", 10);
    try std.testing.expect(n == 40);
}

test "example part 2" {
    const n = try lastConnectionXProduct("day8/input-test.txt");
    try std.testing.expect(n == 25272);
}

test "final part 1" {
    const n = try circuitProduct("day8/input.txt", 1000);
    try std.testing.expect(n == 123234);
}

test "final part 2" {
    const n = try lastConnectionXProduct("day8/input.txt");
    try std.testing.expect(n == 9259958565);
}

pub fn main() !void {
    const part1 = try circuitProduct("day8/input.txt", 1000);
    const part2 = try lastConnectionXProduct("day8/input.txt");
    std.debug.print("part1: {d}\npart2: {d}\n", .{ part1, part2 });
}
