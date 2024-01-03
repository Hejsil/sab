const clap = @import("clap");
const std = @import("std");

const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const testing = std.testing;
const unicode = std.unicode;

const Names = clap.Names;
const Param = clap.Param(clap.Help);

const params = clap.parseParamsComptime(
    \\-h, --help
    \\    Print this message to stdout
    \\
    \\-l, --length <usize>
    \\    The length of the bar (default: 10)
    \\
    \\-m, --min <isize>
    \\    Minimum value (default: 0)
    \\
    \\-M, --max <isize>
    \\    Maximum value (default: 100)
    \\
    \\-s, --steps <str>
    \\    A comma separated list of the steps used to draw the bar (default: ' ,=')
    \\
    \\-t, --type <str>
    \\    The type of bar to draw (options: normal, mark-center) (default: normal)
);

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
    try clap.help(stream, clap.Help, &params, .{});
}

const TypeArg = enum {
    normal,
    @"mark-center",
};

pub fn main() !void {
    const stderr = io.getStdErr().writer();
    const stdout = io.getStdOut().writer();
    const stdin = io.getStdIn().reader();

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var diag = clap.Diagnostic{};
    const args = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(stderr, err) catch {};
        usage(stderr) catch {};
        return err;
    };

    if (args.args.help != 0)
        return try usage(stdout);

    const typ = std.meta.stringToEnum(TypeArg, args.args.type orelse "normal") orelse
        return error.InvalidType;
    const steps = blk: {
        var str = std.ArrayList(u8).init(allocator);
        var res = std.ArrayList([]const u8).init(allocator);
        const list = args.args.steps orelse " ,=";

        var i: usize = 0;
        while (i < list.len) : (i += 1) {
            const c = list[i];
            switch (c) {
                ',' => try res.append(try str.toOwnedSlice()),
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
        try res.append(try str.toOwnedSlice());

        if (res.items.len == 0)
            return error.NoSteps;

        break :blk try res.toOwnedSlice();
    };

    var buf = std.ArrayList(u8).init(allocator);
    while (true) {
        stdin.readUntilDelimiterArrayList(&buf, '\n', math.maxInt(usize)) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };

        const curr = try fmt.parseInt(isize, buf.items, 10);
        try draw(stdout, isize, curr, .{
            .min = args.args.min orelse 0,
            .max = args.args.min orelse 100,
            .len = args.args.length orelse 10,
            .type = switch (typ) {
                .normal => Type.normal,
                .@"mark-center" => Type.mark_center,
            },
            .steps = steps,
        });
        try stdout.writeAll("\n");
    }
}

pub const Type = enum {
    normal,
    mark_center,
};

pub fn DrawOptions(comptime T: type) type {
    return struct {
        min: T = 0,
        max: T = 100,
        len: usize = 10,
        type: Type = .normal,
        steps: []const []const u8 = &[_][]const u8{ " ", "=" },
    };
}

pub fn draw(stream: anytype, comptime T: type, _curr: T, opts: DrawOptions(T)) !void {
    std.debug.assert(opts.steps.len != 0);
    const min = @min(opts.min, opts.max);
    const max = @max(opts.min, opts.max);
    const curr = @min(_curr, max);
    const abs_max: f64 = @floatFromInt(max - min);
    const abs_curr: f64 = @floatFromInt(@max(curr - min, 0));

    const step = abs_max / @as(f64, @floatFromInt(opts.len));

    // Draw upto the center of the bar
    var i: usize = 0;
    while (abs_curr > @as(f64, @floatFromInt(i + 1)) * step) : (i += 1)
        try stream.writeAll(opts.steps[opts.steps.len - 1]);

    const min_index: usize = @intFromBool(opts.type == .mark_center);
    const _max_index = math.sub(usize, opts.steps.len, 1 + min_index) catch 1;
    const max_index = @max(_max_index, 1);
    const mid_steps = opts.steps[min_index..max_index];

    const drawn = @as(f64, @floatFromInt(i)) * step;
    const fullness = (abs_curr - drawn) / step;
    const full_to_index: usize = @intFromFloat(@as(f64, @floatFromInt(mid_steps.len)) * fullness);

    const real_index = @min(full_to_index + min_index, max_index);
    try stream.writeAll(opts.steps[real_index]);
    i += 1;

    // Draw the rest of the bar
    while (i < opts.len) : (i += 1)
        try stream.writeAll(opts.steps[0]);
}

fn testDraw(res: []const u8, curr: isize, opts: DrawOptions(isize)) !void {
    var buf: [100]u8 = undefined;
    var stream = io.fixedBufferStream(&buf);
    try draw(stream.writer(), isize, curr, opts);
    try testing.expectEqualStrings(res, stream.getWritten());
}

test "draw" {
    try testDraw("      ", -1, .{ .min = 0, .max = 6, .len = 6 });
    try testDraw("      ", 0, .{ .min = 0, .max = 6, .len = 6 });
    try testDraw("=     ", 1, .{ .min = 0, .max = 6, .len = 6 });
    try testDraw("==    ", 2, .{ .min = 0, .max = 6, .len = 6 });
    try testDraw("===   ", 3, .{ .min = 0, .max = 6, .len = 6 });
    try testDraw("====  ", 4, .{ .min = 0, .max = 6, .len = 6 });
    try testDraw("===== ", 5, .{ .min = 0, .max = 6, .len = 6 });
    try testDraw("======", 6, .{ .min = 0, .max = 6, .len = 6 });
    try testDraw("======", 7, .{ .min = 0, .max = 6, .len = 6 });
    try testDraw("   ", 0, .{ .min = 0, .max = 6, .len = 3, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("-  ", 1, .{ .min = 0, .max = 6, .len = 3, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("=  ", 2, .{ .min = 0, .max = 6, .len = 3, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("=- ", 3, .{ .min = 0, .max = 6, .len = 3, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("== ", 4, .{ .min = 0, .max = 6, .len = 3, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("==-", 5, .{ .min = 0, .max = 6, .len = 3, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("===", 6, .{ .min = 0, .max = 6, .len = 3, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("=     ", -1, .{ .min = 0, .max = 6, .len = 6, .type = .mark_center, .steps = &[_][]const u8{ " ", "=" } });
    try testDraw("=     ", 0, .{ .min = 0, .max = 6, .len = 6, .type = .mark_center, .steps = &[_][]const u8{ " ", "=" } });
    try testDraw("=     ", 1, .{ .min = 0, .max = 6, .len = 6, .type = .mark_center, .steps = &[_][]const u8{ " ", "=" } });
    try testDraw("==    ", 2, .{ .min = 0, .max = 6, .len = 6, .type = .mark_center, .steps = &[_][]const u8{ " ", "=" } });
    try testDraw("===   ", 3, .{ .min = 0, .max = 6, .len = 6, .type = .mark_center, .steps = &[_][]const u8{ " ", "=" } });
    try testDraw("====  ", 4, .{ .min = 0, .max = 6, .len = 6, .type = .mark_center, .steps = &[_][]const u8{ " ", "=" } });
    try testDraw("===== ", 5, .{ .min = 0, .max = 6, .len = 6, .type = .mark_center, .steps = &[_][]const u8{ " ", "=" } });
    try testDraw("======", 6, .{ .min = 0, .max = 6, .len = 6, .type = .mark_center, .steps = &[_][]const u8{ " ", "=" } });
    try testDraw("======", 7, .{ .min = 0, .max = 6, .len = 6, .type = .mark_center, .steps = &[_][]const u8{ " ", "=" } });
    try testDraw("-  ", 0, .{ .min = 0, .max = 6, .len = 3, .type = .mark_center, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("-  ", 1, .{ .min = 0, .max = 6, .len = 3, .type = .mark_center, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("-  ", 2, .{ .min = 0, .max = 6, .len = 3, .type = .mark_center, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("=- ", 3, .{ .min = 0, .max = 6, .len = 3, .type = .mark_center, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("=- ", 4, .{ .min = 0, .max = 6, .len = 3, .type = .mark_center, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("==-", 5, .{ .min = 0, .max = 6, .len = 3, .type = .mark_center, .steps = &[_][]const u8{ " ", "-", "=" } });
    try testDraw("==-", 6, .{ .min = 0, .max = 6, .len = 3, .type = .mark_center, .steps = &[_][]const u8{ " ", "-", "=" } });
}
