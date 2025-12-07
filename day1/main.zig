const std = @import("std");

fn amountEndedOnZero(reader: *std.Io.Reader) !usize {
    var acc: u8 = 50;
    var num_zeroes: usize = 0;

    while (true) {
        const action = try reader.takeDelimiter('\n') orelse break;

        std.debug.assert(action.len > 0);

        const raw = try std.fmt.parseInt(u16, action[1..], 10);
        const delta: u8 = @intCast(@mod(raw, 100));

        switch (action[0]) {
            'L' => acc = if (delta > acc) 100 - (delta - acc) else acc - delta,
            'R' => acc = @mod(acc + delta, 100),
            else => unreachable,
        }

        if (acc == 0) num_zeroes += 1;
    }

    return num_zeroes;
}

fn amountRolledOnZero(reader: *std.Io.Reader) !usize {
    var acc: u8 = 50;
    var num_zeroes: usize = 0;

    while (true) {
        const action = try reader.takeDelimiter('\n') orelse break;

        std.debug.assert(action.len > 0);

        const raw = try std.fmt.parseInt(u16, action[1..], 10);

        const delta: u8 = @intCast(@mod(raw, 100));
        const rolls: usize = @intCast((raw - @as(u16, @intCast(delta))) / 100);
        num_zeroes += rolls;

        switch (action[0]) {
            'L' => {
                if (delta >= acc) {
                    if (acc != 0) {
                        // This zero has already been counted when we arrived
                        // here.
                        num_zeroes += 1;
                    }
                    acc = @mod(100 - (delta - acc), 100);
                } else {
                    acc -= delta;
                }
            },
            'R' => {
                if (acc + delta >= 100) {
                    num_zeroes += 1;
                }
                acc = @mod(acc + delta, 100);
            },
            else => unreachable,
        }
    }

    return num_zeroes;
}

test "example" {
    var file = try std.fs.cwd().openFile("day1/input-test.txt", .{});
    defer file.close();

    {
        var buf: [4096]u8 = undefined;
        var reader = file.reader(&buf);
        const amount = try amountEndedOnZero(&reader.interface);
        try std.testing.expect(amount == 3);
    }

    {
        var buf: [4096]u8 = undefined;
        var reader = file.reader(&buf);
        const amount = try amountRolledOnZero(&reader.interface);
        std.debug.print("amount rolled = {d}\n", .{amount});
        try std.testing.expect(amount == 6);
    }
}

test "final" {
    var file = try std.fs.cwd().openFile("day1/input.txt", .{});
    defer file.close();

    {
        var buf: [4096]u8 = undefined;
        var reader = file.reader(&buf);
        const amount = try amountEndedOnZero(&reader.interface);
        try std.testing.expect(amount == 1064);
    }

    {
        var buf: [4096]u8 = undefined;
        var reader = file.reader(&buf);
        const amount = try amountRolledOnZero(&reader.interface);
        std.debug.print("amount rolled = {d}\n", .{amount});
        try std.testing.expect(amount == 6122);
    }
}

pub fn main() !void {
    var file = try std.fs.cwd().openFile("day1/input.txt", .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    const amount = try amountRolledOnZero(&reader.interface);
    std.debug.print("{d}\n", .{amount});
}
