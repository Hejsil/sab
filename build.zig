const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    _ = b.addModule("sab", .{ .source_file = .{ .path = "src/main.zig" } });

    const exe = b.addExecutable(.{
        .name = "sab",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addAnonymousModule("clap", .{ .source_file = .{ .path = "lib/zig-clap/clap.zig" } });
    exe.install();

    const test_step = b.step("test", "");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&tests.step);

    b.default_step.dependOn(&exe.step);
}
