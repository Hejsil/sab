const clap = @import("zig-clap");
const std = @import("std");

const testing = std.testing;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const unicode = std.unicode;

const Names = clap.Names;
const Param = clap.Param(clap.Help);

const params = comptime blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]Param{
        clap.parseParam("-h, --help                       print this message to stdout") catch unreachable,
        clap.parseParam("-l, --length <NUM>               the length of the bar (default: 10)") catch unreachable,
        clap.parseParam("-m, --min    <NUM>               minimum value (default: 0)") catch unreachable,
        clap.parseParam("-M, --max    <NUM>               maximum value (default: 100)") catch unreachable,
        clap.parseParam("-s, --steps  <LIST>              a comma separated list of the steps used to draw the bar (default: ' ,=')") catch unreachable,
        clap.parseParam("-t, --type <normal|mark-center>  the type of bar to draw (default: normal)") catch unreachable,
    };
};

fn usage(stream: anytype) !void {
    try stream.writeAll(
        \\Usage: sab [OPTION]...
        \\sab will draw bars/spinners based on the values piped in through
        \\stdin.
        \\
        \\To draw a simple bar, simply pipe a value between 0-100 into sab:
        \\echo 35 | sab
        \\====      
        \\
        \\You can customize your bar with the '-s, --steps' option:
        \\echo 35 | sab -s ' ,-,='
        \\===-      
        \\
        \\`sab` has two ways of drawing bars, which can be chosen with the `-t, --type` option:
        \\echo 50 | sab -s ' ,|,='
        \\=====     
        \\echo 55 | sab -s ' ,|,='
        \\=====|    
        \\echo 50 | sab -s ' ,|,=' -t mark-center
        \\====|     
        \\echo 55 | sab -s ' ,|,=' -t mark-center
        \\=====|    
        \\
        \\To draw a simple spinner, simply set the length of the bar to 1
        \\and set max to be the last step:
        \\echo 2 | sab -l 1 -M 3 -s '/,-,\,|'
        \\\
        \\
        \\sab will draw multible lines, one for each line piped into it.
        \\echo -e '0\n1\n2\n3' | sab -l 1 -M 3 -s '/,-,\,|'
        \\/
        \\-
        \\\
        \\|
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

const Type = enum {
    normal,
    @"mark-center",
};

pub fn main() !void {
    const stderr = io.getStdErr().outStream();
    const stdout = io.getStdOut().outStream();
    const stdin = io.getStdIn().inStream();

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var diag = clap.Diagnostic{};
    var args = clap.parse(clap.Help, &params, allocator, &diag) catch |err| {
        diag.report(stderr, err) catch {};
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const min = try fmt.parseInt(isize, args.option("--min") orelse "0", 10);
    const max = try fmt.parseInt(isize, args.option("--max") orelse "100", 10);
    const len = try fmt.parseUnsigned(usize, args.option("--length") orelse "10", 10);
    const typ = std.meta.stringToEnum(Type, args.option("--type") orelse "normal") orelse return error.InvalidType;
    const steps = blk: {
        var str = std.ArrayList(u8).init(allocator);
        var res = std.ArrayList([]const u8).init(allocator);
        const list = args.option("--steps") orelse " ,=";

        var i: usize = 0;
        while (i < list.len) : (i += 1) {
            const c = list[i];
            switch (c) {
                ',' => try res.append(str.toOwnedSlice()),
                '\\' => {
                    i += 1;
                    const c2 = if (i < list.len) list[i] else 0;
                    switch (c2) {
                        ',', '\\' => try str.append(c2),
                        else => return error.InvalidEscape,
                    }
                },
                else => try str.append(c),
            }
        }
        try res.append(str.toOwnedSlice());

        if (res.items.len == 0)
            return error.NoSteps;

        break :blk res.toOwnedSlice();
    };

    var buf = std.ArrayList(u8).init(allocator);
    while (true) {
        stdin.readUntilDelimiterArrayList(&buf, '\n', math.maxInt(usize)) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };

        const curr = try fmt.parseInt(isize, buf.items, 10);
        try draw(stdout, curr, min, max, len, typ, steps);
        try stdout.writeAll("\n");
    }
}

fn draw(stream: anytype, curr: isize, min: isize, max: isize, len: usize, typ: Type, steps: []const []const u8) !void {
    std.debug.assert(steps.len != 0);
    const abs_max = @intToFloat(f64, try math.cast(usize, max - min));
    const abs_curr = @intToFloat(f64, math.max(math.min(curr, max) - min, 0));

    const step = abs_max / @intToFloat(f64, len);

    // Draw upto the center of the bar
    var i: usize = 0;
    while (abs_curr > @intToFloat(f64, i + 1) * step) : (i += 1)
        try stream.writeAll(steps[steps.len - 1]);

    const min_index = @boolToInt(typ == .@"mark-center");
    const max_index = math.max(math.sub(usize, steps.len, @as(usize, 1) + @boolToInt(typ == .@"mark-center")) catch 1, 1);

    const drawn = @intToFloat(f64, i) * step;
    const fullness = (abs_curr - drawn) / step;
    const full_to_index = @floatToInt(usize, @intToFloat(f64, steps[min_index..max_index].len) * fullness);

    const real_index = math.min(full_to_index + min_index, max_index);
    try stream.writeAll(steps[real_index]);
    i += 1;

    // Draw the rest of the bar
    while (i < len) : (i += 1)
        try stream.writeAll(steps[0]);
}

fn testDraw(res: []const u8, curr: isize, min: isize, max: isize, len: usize, typ: Type, steps: []const []const u8) void {
    var buf: [100]u8 = undefined;
    var stream = io.fixedBufferStream(&buf);
    draw(stream.outStream(), curr, min, max, len, typ, steps) catch @panic("");
    testing.expectEqualSlices(u8, res, stream.getWritten());
}

test "draw" {
    testDraw("      ", -1, 0, 6, 6, .normal, &[_][]const u8{ " ", "=" });
    testDraw("      ", 0, 0, 6, 6, .normal, &[_][]const u8{ " ", "=" });
    testDraw("=     ", 1, 0, 6, 6, .normal, &[_][]const u8{ " ", "=" });
    testDraw("==    ", 2, 0, 6, 6, .normal, &[_][]const u8{ " ", "=" });
    testDraw("===   ", 3, 0, 6, 6, .normal, &[_][]const u8{ " ", "=" });
    testDraw("====  ", 4, 0, 6, 6, .normal, &[_][]const u8{ " ", "=" });
    testDraw("===== ", 5, 0, 6, 6, .normal, &[_][]const u8{ " ", "=" });
    testDraw("======", 6, 0, 6, 6, .normal, &[_][]const u8{ " ", "=" });
    testDraw("======", 7, 0, 6, 6, .normal, &[_][]const u8{ " ", "=" });
    testDraw("   ", 0, 0, 6, 3, .normal, &[_][]const u8{ " ", "-", "=" });
    testDraw("-  ", 1, 0, 6, 3, .normal, &[_][]const u8{ " ", "-", "=" });
    testDraw("=  ", 2, 0, 6, 3, .normal, &[_][]const u8{ " ", "-", "=" });
    testDraw("=- ", 3, 0, 6, 3, .normal, &[_][]const u8{ " ", "-", "=" });
    testDraw("== ", 4, 0, 6, 3, .normal, &[_][]const u8{ " ", "-", "=" });
    testDraw("==-", 5, 0, 6, 3, .normal, &[_][]const u8{ " ", "-", "=" });
    testDraw("===", 6, 0, 6, 3, .normal, &[_][]const u8{ " ", "-", "=" });
    testDraw("=     ", -1, 0, 6, 6, .@"mark-center", &[_][]const u8{ " ", "=" });
    testDraw("=     ", 0, 0, 6, 6, .@"mark-center", &[_][]const u8{ " ", "=" });
    testDraw("=     ", 1, 0, 6, 6, .@"mark-center", &[_][]const u8{ " ", "=" });
    testDraw("==    ", 2, 0, 6, 6, .@"mark-center", &[_][]const u8{ " ", "=" });
    testDraw("===   ", 3, 0, 6, 6, .@"mark-center", &[_][]const u8{ " ", "=" });
    testDraw("====  ", 4, 0, 6, 6, .@"mark-center", &[_][]const u8{ " ", "=" });
    testDraw("===== ", 5, 0, 6, 6, .@"mark-center", &[_][]const u8{ " ", "=" });
    testDraw("======", 6, 0, 6, 6, .@"mark-center", &[_][]const u8{ " ", "=" });
    testDraw("======", 7, 0, 6, 6, .@"mark-center", &[_][]const u8{ " ", "=" });
    testDraw("-  ", 0, 0, 6, 3, .@"mark-center", &[_][]const u8{ " ", "-", "=" });
    testDraw("-  ", 1, 0, 6, 3, .@"mark-center", &[_][]const u8{ " ", "-", "=" });
    testDraw("-  ", 2, 0, 6, 3, .@"mark-center", &[_][]const u8{ " ", "-", "=" });
    testDraw("=- ", 3, 0, 6, 3, .@"mark-center", &[_][]const u8{ " ", "-", "=" });
    testDraw("=- ", 4, 0, 6, 3, .@"mark-center", &[_][]const u8{ " ", "-", "=" });
    testDraw("==-", 5, 0, 6, 3, .@"mark-center", &[_][]const u8{ " ", "-", "=" });
    testDraw("==-", 6, 0, 6, 3, .@"mark-center", &[_][]const u8{ " ", "-", "=" });
}
