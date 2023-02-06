const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardOptimizeOption(.{});

    b.addModule(.{
        .name = "strided-arrays",
        .source_file = .{ .path = "src/strided_array.zig" },
    });

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .optimize = mode,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    b.default_step = test_step;
}
