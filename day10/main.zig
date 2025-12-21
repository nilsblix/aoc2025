const std = @import("std");

const LedState = struct {
    items: u16,

    fn initFromBuffer(buf: []const u8) !LedState {
        var leds = LedState{ .items = 0 };
        for (buf, 0..) |b, i| {
            switch (b) {
                '#' => leds.items |= @as(u16, 1) << @intCast(i),
                '.' => continue,
                else => return error.Unexpected,
            }
        }
        return leds;
    }
};

const Button = struct {
    items: u16,

    fn initFromBuffer(buf: []const u8) !Button {
        var btn = Button{ .items = 0 };

        for (buf) |b| {
            switch (b) {
                // Looks like the buttons only contain indices from 0 through 9 :)
                '0'...'9' => {
                    btn.items |= @as(u16, 1) << @intCast(b - '0');
                },
                ',' => continue,
                else => return error.Unexpected,
            }
        }

        return btn;
    }
};

const JoltageState = struct {
    items: [16]u16 = .{ 0 } ** 16,
};

fn parseDesiredState(reader: *std.Io.Reader) !LedState {
    if (try reader.takeByte() != '[') {
        return error.Unexpected;
    }

    const line = try reader.takeDelimiter(']') orelse unreachable;
    return try LedState.initFromBuffer(@ptrCast(line));
}

fn parseButtons(alloc: std.mem.Allocator, reader: *std.Io.Reader) ![]Button {
    var buttons = std.ArrayList(Button).empty;
    defer buttons.deinit(alloc);

    while (true) {
        if (try reader.peekByte() == '{') {
            break;
        }

        if (try reader.takeByte() != '(') {
            return error.Unexpected;
        }

        const inside = try reader.takeDelimiter(')') orelse break;

        const btn = try Button.initFromBuffer(@ptrCast(inside));
        try buttons.append(alloc, btn);

        const taken = try reader.takeByte();
        if (taken != ' ') {
            return error.Unexpected;
        }
    }

    return try buttons.toOwnedSlice(alloc);
}

fn parseJoltages(reader: *std.Io.Reader) !JoltageState {
    if (try reader.takeByte() != '{') {
        return error.Unexpected;
    }

    var state = JoltageState{};

    var i: usize = 0;
    while (true) {
        const inside = try reader.takeDelimiter(',') orelse break;
        const trimmed = std.mem.trim(u8, inside, "}");
        const num = try std.fmt.parseInt(u16, trimmed, 10);
        state.items[i] = num;
        i += 1;
    }

    return state;
}

test "init ledstate from buffer" {
    const b = "..#.###";
    var state = try LedState.initFromBuffer(@ptrCast(b));
    try std.testing.expectEqual(state.items, 0b1110100);

    const b2 = "#.#.###..";
    state = try LedState.initFromBuffer(@ptrCast(b2));
    try std.testing.expectEqual(state.items, 0b001110101);
}

test "parse full line example with leds buttons and joltages" {
    const line = "[.##.] (3) (1,3) (2) (2,3) (0,2) (0,1) {3,5,4,7}";
    var line_reader = std.Io.Reader.fixed(line[0..]);

    const desired_leds = try parseDesiredState(&line_reader);
    try std.testing.expectEqual(@as(u16, 0b0110), desired_leds.items);

    try std.testing.expectEqual(@as(u8, ' '), try line_reader.takeByte());

    const buttons = try parseButtons(std.testing.allocator, &line_reader);
    defer std.testing.allocator.free(buttons);
    try std.testing.expectEqual(@as(usize, 6), buttons.len);
    try std.testing.expectEqual(@as(u16, 1 << 3), buttons[0].items);
    try std.testing.expectEqual(@as(u16, (1 << 1) | (1 << 3)), buttons[1].items);
    try std.testing.expectEqual(@as(u16, 1 << 2), buttons[2].items);
    try std.testing.expectEqual(@as(u16, (1 << 2) | (1 << 3)), buttons[3].items);
    try std.testing.expectEqual(@as(u16, (1 << 0) | (1 << 2)), buttons[4].items);
    try std.testing.expectEqual(@as(u16, (1 << 0) | (1 << 1)), buttons[5].items);

    const desired_jolts = try parseJoltages(&line_reader);
    try std.testing.expectEqual(@as(u16, 3), desired_jolts.items[0]);
    try std.testing.expectEqual(@as(u16, 5), desired_jolts.items[1]);
    try std.testing.expectEqual(@as(u16, 4), desired_jolts.items[2]);
    try std.testing.expectEqual(@as(u16, 7), desired_jolts.items[3]);
    try std.testing.expectEqual(@as(u16, 0), desired_jolts.items[4]);
}

test "parse full line with large joltage value" {
    const line = "[#] (0) {279}";
    var line_reader = std.Io.Reader.fixed(line[0..]);

    const desired_leds = try parseDesiredState(&line_reader);
    try std.testing.expectEqual(@as(u16, 1), desired_leds.items);

    try std.testing.expectEqual(@as(u8, ' '), try line_reader.takeByte());

    const buttons = try parseButtons(std.testing.allocator, &line_reader);
    defer std.testing.allocator.free(buttons);
    try std.testing.expectEqual(@as(usize, 1), buttons.len);
    try std.testing.expectEqual(@as(u16, 1), buttons[0].items);

    const desired_jolts = try parseJoltages(&line_reader);
    try std.testing.expectEqual(@as(u16, 279), desired_jolts.items[0]);
    try std.testing.expectEqual(@as(u16, 0), desired_jolts.items[1]);
}

const Queue = struct {
    ring: []usize,
    head: usize,
    tail: usize,
    len: usize,

    fn empty(self: *const Queue) bool {
        return self.len == 0;
    }

    fn push(self: *Queue, idx: usize) void {
        std.debug.assert(self.len < self.ring.len);
        self.ring[self.tail] = idx;
        self.tail += 1;
        if (self.tail == self.ring.len) self.tail = 0;
        self.len += 1;
    }

    fn pop(self: *Queue) usize {
        const idx = self.ring[self.head];
        self.head += 1;
        if (self.head == self.ring.len) self.head = 0;
        self.len -= 1;
        return idx;
    }
};

const Solution = struct {
    depth: usize,
    buttons: []Button,

    fn deinit(self: *Solution, alloc: std.mem.Allocator) void {
        alloc.free(self.buttons);
    }
};

const LedBfs = struct {
    const Node = struct {
        prev_idx: ?usize,
        button_to_prev: Button,
        state: LedState,
        depth: u16,

        fn new(self: *const Node, idx: usize, button: Button) Node {
            return .{
                .prev_idx = idx,
                .button_to_prev = button,
                .state = .{ .items = self.state.items ^ button.items },
                .depth = self.depth + 1,
            };
        }
    };

    const N: usize = 1 << 16;

    nodes: []Node,
    next_node: usize,
    q: Queue,
    visited: std.bit_set.StaticBitSet(N),

    fn storeNode(self: *LedBfs, node: Node) usize {
        self.nodes[self.next_node] = node;
        self.next_node += 1;
        return self.next_node - 1;
    }

    fn getSolution(self: *const LedBfs, alloc: std.mem.Allocator, end_idx: usize) !Solution {
        const end_node = self.nodes[end_idx];
        const depth = @as(usize, @intCast(end_node.depth));

        var out = try alloc.alloc(Button, depth);

        var idx = end_idx;
        var k = depth;
        while (k > 0) {
            k -= 1;
            const cur = self.nodes[idx];
            out[k] = cur.button_to_prev;
            idx = cur.prev_idx.?;
        }

        return .{ .depth = end_node.depth, .buttons = out };
    }

    fn solve(self: *LedBfs, alloc: std.mem.Allocator, desired_state: LedState, buttons: []const Button) !?Solution {
        while (!self.q.empty()) {
            const parent_idx = self.q.pop();
            const parent = self.nodes[parent_idx];

            for (buttons) |b| {
                const child = parent.new(parent_idx, b);
                const s: usize = @as(usize, @intCast(child.state.items));

                if (self.visited.isSet(s)) continue;
                self.visited.set(s);

                const child_idx = self.storeNode(child);

                if (child.state.items == desired_state.items) {
                    return try self.getSolution(alloc, child_idx);
                }

                self.q.push(child_idx);
            }
        }

        return null;
    }
};

fn stepsToDesiredLeds(alloc: std.mem.Allocator, desired_state: LedState, buttons: []const Button) !usize {
    const possible_states = 1 << 16;
    var node_buf: [possible_states]LedBfs.Node = undefined;
    var q_buf: [possible_states]usize = undefined;

    var bfs = LedBfs{
        .nodes = &node_buf,
        .next_node = 0,
        .q = .{
            .ring = &q_buf,
            .head = 0,
            .tail = 0,
            .len = 0,
        },
        .visited = .initEmpty(),
    };

    const source_node = LedBfs.Node{
        .prev_idx = null,
        .button_to_prev = Button{ .items = 0 },
        .state = .{ .items = 0 },
        .depth = 0,
    };

    const root_idx = bfs.storeNode(source_node);
    bfs.visited.set(@as(usize, @intCast(source_node.state.items)));
    bfs.q.push(root_idx);

    if (desired_state.items == 0) return 0;

    var solution = try bfs.solve(alloc, desired_state, buttons) orelse return error.NoSolution;
    defer solution.deinit(alloc);

    return solution.depth;
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

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    const input_path = if (args.len > 1) args[1] else "day10/input.txt";

    var f = try std.fs.cwd().openFile(input_path, .{});
    defer f.close();

    var reader_buf: [4096]u8 = undefined;
    var reader = f.reader(&reader_buf);

    var sum_leds: usize = 0;
    const sum_jolts: usize = 0;
    while (true) {
        var line = try reader.interface.takeDelimiter('\n') orelse break;

        var line_reader = std.Io.Reader.fixed(line[0..]);
        const desired_leds = try parseDesiredState(&line_reader);

        std.debug.assert(try line_reader.takeByte() == ' ');

        const buttons = try parseButtons(alloc, &line_reader);
        defer alloc.free(buttons);

        const led_steps = try stepsToDesiredLeds(alloc, desired_leds, buttons[0..]);
        sum_leds += led_steps;

        const desired_jolts = try parseJoltages(&line_reader);
        _ = desired_jolts;
    }

    std.debug.print("steps to led: {d}, steps to joltages: {d}\n", .{sum_leds, sum_jolts});
}
