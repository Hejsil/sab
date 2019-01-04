const clap = @import("zig-clap");
const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;

const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const params = []Param{
    Param.flag(
        "print this message to stdout",
        Names.both("help"),
    ),
    Param.option(
        "the length of the bar (default: 10)",
        Names.both("length"),
    ),
    Param.option(
        "mininum value (default: 0)",
        Names.both("min"),
    ),
    Param.option(
        "maximum value (default: 100)",
        Names{ .short = 'M', .long = "max"},
    ),
    Param.positional(""),
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: sab [OPTION]... [CURR]...
        \\Given a min, max and current value, sab will draw bars/spinners
        \\to stdout. The format of the bar/spinner is read from stdin and
        \\is a line seperated lists of steps.
        \\
        \\To draw a simple bar, simply pipe your empty and full chars into
        \\sab, and give it the current value:
        \\echo -e '.\n=' | sab 35
        \\====......
        \\
        \\For a more fine grained bar, simply pipe in more steps:
        \\echo -e '.\n-\n=' | sab 35
        \\===-......
        \\
        \\To draw a simple spinner, simply set the length of the bar to 1
        \\and set min to 0 and max to be the last step:
        \\echo -e '/\n-\n\\\n|' | sab -l 1 -M 3 3
        \\|
        \\
        \\sab will draw multible lines if provided with multible current
        \\values.
        \\echo -e '/\n-\n\\\n|' | sab -l 1 -M 3 0 1 2 3
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

pub fn main() anyerror!void {
    const stderr = &(try io.getStdErr()).outStream().stream;
    const stdout = &(try io.getStdOut()).outStream().stream;
    const stdin = &(try io.getStdIn()).inStream().stream;

    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    var arena = heap.ArenaAllocator.init(&direct_allocator.allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var arg_iter = clap.args.OsIterator.init(allocator);
    const iter = &arg_iter.iter;
    _ = iter.next() catch undefined;

    var args = Clap.parse(allocator, clap.args.OsIterator.Error, iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const min = try fmt.parseInt(isize, args.option("--min") orelse "0", 10);
    const max = try fmt.parseInt(isize, args.option("--max") orelse "100", 10);
    const len = try fmt.parseUnsigned(usize, args.option("--length") orelse "10", 10);

    const steps = blk: {
        const lines = try stdin.readAllAlloc(allocator, 1024 * 1024);
        const res = try split(allocator, lines, "\n");
        if (res.len == 0)
            return error.NoSteps;

        break :blk res;
    };

    for (args.positionals()) |curr_str| {
        const curr = try fmt.parseInt(isize, curr_str, 10);
        try draw(stdout, curr, min, max, len, steps);
        try stdout.write("\n");
    }
}

fn split(allocator: *mem.Allocator, buffer: []const u8, split_bytes: []const u8) ![][]const u8 {
    var res = std.ArrayList([]const u8).init(allocator);
    defer res.deinit();

    var iter = mem.split(buffer, split_bytes);
    while (iter.next()) |s|
        try res.append(s);

    return res.toOwnedSlice();
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
    draw(&stream.stream, curr, min, max, len, steps) catch unreachable;
    debug.assert(mem.eql(u8, res, stream.getWritten()));
}

test "draw" {
    testDraw("      ", -1, 0, 6, 6, [][]const u8{" ", "="});
    testDraw("      ", 0, 0, 6, 6, [][]const u8{" ", "="});
    testDraw("=     ", 1, 0, 6, 6, [][]const u8{" ", "="});
    testDraw("==    ", 2, 0, 6, 6, [][]const u8{" ", "="});
    testDraw("===   ", 3, 0, 6, 6, [][]const u8{" ", "="});
    testDraw("====  ", 4, 0, 6, 6, [][]const u8{" ", "="});
    testDraw("===== ", 5, 0, 6, 6, [][]const u8{" ", "="});
    testDraw("======", 6, 0, 6, 6, [][]const u8{" ", "="});
    testDraw("======", 7, 0, 6, 6, [][]const u8{" ", "="});
    testDraw("   ", 0, 0, 6, 3, [][]const u8{" ", "-", "="});
    testDraw("-  ", 1, 0, 6, 3, [][]const u8{" ", "-", "="});
    testDraw("=  ", 2, 0, 6, 3, [][]const u8{" ", "-", "="});
    testDraw("=- ", 3, 0, 6, 3, [][]const u8{" ", "-", "="});
    testDraw("== ", 4, 0, 6, 3, [][]const u8{" ", "-", "="});
    testDraw("==-", 5, 0, 6, 3, [][]const u8{" ", "-", "="});
    testDraw("===", 6, 0, 6, 3, [][]const u8{" ", "-", "="});
}
