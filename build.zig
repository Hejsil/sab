const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    _ = b.addModule("sab", .{ .root_source_file = .{ .path = "src/main.zig" } });

    const exe = b.addExecutable(.{
        .name = "sab",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addAnonymousImport("clap", .{
        .root_source_file = .{ .path = "lib/zig-clap/clap.zig" },
    });

    const test_step = b.step("test", "");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    b.installArtifact(exe);
}
