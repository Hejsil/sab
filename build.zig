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
    const install_exe = b.addInstallArtifact(exe);
    exe.addAnonymousModule("clap", .{ .source_file = .{ .path = "lib/zig-clap/clap.zig" } });

    const test_step = b.step("test", "");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    b.default_step.dependOn(&install_exe.step);
}
