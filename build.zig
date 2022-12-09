const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});
    const exe = b.addExecutable("sab", "src/main.zig");
    exe.addPackagePath("zig-clap", "lib/zig-clap/clap.zig");
    exe.setBuildMode(mode);
    exe.setTarget(target);
    exe.install();

    const test_step = b.step("test", "");
    const tests = b.addTest("src/main.zig");
    tests.setBuildMode(mode);
    tests.setTarget(target);
    test_step.dependOn(&tests.step);

    b.default_step.dependOn(&exe.step);
}
