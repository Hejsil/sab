const clap = @import("zig-clap");
const std = @import("std");

const testing = std.testing;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const unicode = std.unicode;

const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = [_]Param{
    Param{
        .id = "print this message to stdout",
        .names = Names{ .short = 'h', .long = "help" },
    },
    Param{
        .id = "the length of the bar (default: 10)",
        .names = Names{ .short = 'l', .long = "length" },
        .takes_value = true,
    },
    Param{
        .id = "mininum value (default: 0)",
        .names = Names{ .short = 'm', .long = "min" },
        .takes_value = true,
    },
    Param{
        .id = "maximum value (default: 100)",
        .names = Names{ .short = 'M', .long = "max" },
        .takes_value = true,
    },
    Param{
        .id = "list of steps (default: ' =')",
        .names = Names{ .short = 's', .long = "steps" },
        .takes_value = true,
    },
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: sab [OPTION]...
        \\sab will draw bars/spinners based on the values piped in through
        \\stdin.
        \\
        \\To draw a simple bar, simply pipe a value between 0-100 into sab:
        \\echo 35 | sab
        \\====      
        \\
        \\You can customize your bar with the '--steps' option:
        \\echo 35 | sab -s ' -='
        \\===-      
        \\
        \\To draw a simple spinner, simply set the length of the bar to 1
        \\and set max to be the last step:
        \\echo 2 | sab -l 1 -M 3 -s '/-\|'
        \\\
        \\
        \\sab will draw multible lines, one for each line piped into it.
        \\echo -e '0\n1\n2\n3' | sab -l 1 -M 3 -s '/-\|'
        \\/
        \\-
        \\\
        \\|
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

pub fn main() !void {
    const stderr = &(try io.getStdErr()).outStream().stream;
    const stdout = &(try io.getStdOut()).outStream().stream;
    const stdin = &(try io.getStdIn()).inStream().stream;

    var arena = heap.ArenaAllocator.init(heap.direct_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const min = try fmt.parseInt(isize, args.option("--min") orelse "0", 10);
    const max = try fmt.parseInt(isize, args.option("--max") orelse "100", 10);
    const len = try fmt.parseUnsigned(usize, args.option("--length") orelse "10", 10);
    const steps = blk: {
        const list = args.option("--steps") orelse " =";
        const utf8_view = try unicode.Utf8View.init(list);
        var res = std.ArrayList([]const u8).init(allocator);
        var utf8_iter = utf8_view.iterator();
        while (utf8_iter.nextCodepointSlice()) |step|
            try res.append(step);

        if (res.len == 0)
            return error.NoSteps;

        break :blk res.toOwnedSlice();
    };

    var buf = try std.Buffer.initSize(allocator, 0);
    while (io.readLineFrom(stdin, &buf)) |str| {
        defer buf.shrink(0);

        const curr = try fmt.parseInt(isize, str, 10);
        try draw(stdout, curr, min, max, len, steps);
        try stdout.write("\n");
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }
}

fn draw(stream: var, curr: isize, min: isize, max: isize, len: usize, steps: []const []const u8) !void {
    const abs_max = @intToFloat(f64, try math.cast(usize, max - min));
    var abs_curr = @intToFloat(f64, math.max(curr - min, 0));

    const step = abs_max / @intToFloat(f64, len);

    var i: usize = 0;
    while (i < len) : (i += 1) {
        const drawed = @intToFloat(f64, i) * step;
        const fullness = math.max((abs_curr - drawed) / step, 0);
        const full_to_index = @floatToInt(usize, @intToFloat(f64, steps.len) * fullness);
        const real_index = math.min(full_to_index, steps.len - 1);
        try stream.write(steps[real_index]);
    }
}

fn testDraw(res: []const u8, curr: isize, min: isize, max: isize, len: usize, steps: []const []const u8) void {
    var buf: [100]u8 = undefined;
    var stream = io.SliceOutStream.init(buf[0..]);
    draw(&stream.stream, curr, min, max, len, steps) catch @panic("");
    testing.expectEqualSlices(u8, res, stream.getWritten());
}

test "draw" {
    testDraw("      ", -1, 0, 6, 6, [_][]const u8{ " ", "=" });
    testDraw("      ", 0, 0, 6, 6, [_][]const u8{ " ", "=" });
    testDraw("=     ", 1, 0, 6, 6, [_][]const u8{ " ", "=" });
    testDraw("==    ", 2, 0, 6, 6, [_][]const u8{ " ", "=" });
    testDraw("===   ", 3, 0, 6, 6, [_][]const u8{ " ", "=" });
    testDraw("====  ", 4, 0, 6, 6, [_][]const u8{ " ", "=" });
    testDraw("===== ", 5, 0, 6, 6, [_][]const u8{ " ", "=" });
    testDraw("======", 6, 0, 6, 6, [_][]const u8{ " ", "=" });
    testDraw("======", 7, 0, 6, 6, [_][]const u8{ " ", "=" });
    testDraw("   ", 0, 0, 6, 3, [_][]const u8{ " ", "-", "=" });
    testDraw("-  ", 1, 0, 6, 3, [_][]const u8{ " ", "-", "=" });
    testDraw("=  ", 2, 0, 6, 3, [_][]const u8{ " ", "-", "=" });
    testDraw("=- ", 3, 0, 6, 3, [_][]const u8{ " ", "-", "=" });
    testDraw("== ", 4, 0, 6, 3, [_][]const u8{ " ", "-", "=" });
    testDraw("==-", 5, 0, 6, 3, [_][]const u8{ " ", "-", "=" });
    testDraw("===", 6, 0, 6, 3, [_][]const u8{ " ", "-", "=" });
}
