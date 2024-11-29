const std = @import("std");

pub fn build(b: *std.Build) void {
    // const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .musl } });
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "doaz",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // .linkage = .static,
    });

    // exe.linkSystemLibrary2("bsd", .{
        // .use_pkg_config = .force,
        // .preferred_link_mode = .dynamic,
        // .needed = true,
    // });

    // zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl
    exe.linkLibC();
    exe.linkSystemLibrary("crypt");
    // exe.linkSystemLibrary("libbsd");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const id_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/id.zig"),
        .target = target,
        .optimize = optimize,
    });

    id_unit_tests.linkLibC();

    const test_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/auth.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_unit_tests.linkLibC();
    test_unit_tests.linkSystemLibrary("crypt");

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const run_id_unit_tests = b.addRunArtifact(id_unit_tests);
    const test_id_unit_tests = b.addRunArtifact(test_unit_tests);

    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_id_unit_tests.step);
    test_step.dependOn(&test_id_unit_tests.step);
}
