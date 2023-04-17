const std = @import("std");

pub fn build(b: *std.Build) void {
    const mode = b.standardOptimizeOption(.{});

    _ = b.addModule("strided-arrays", .{
        .source_file = .{ .path = "src/strided_array.zig" },
    });

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .optimize = mode,
    });
    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    b.default_step = test_step;
}
