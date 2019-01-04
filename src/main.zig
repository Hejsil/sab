const clap = @import("zig-clap");
const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const unicode = std.unicode;

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
    Param.option(
        "list of steps (default: ' =')",
        Names.both("steps"),
    ),
    Param.positional(""),
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
