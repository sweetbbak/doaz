const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    // const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .musl } });
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // add options for using in code
    const opts = b.addOptions();
    // const shadow_file = b.option([]const u8, "shadow", "expected path to the shadow file") orelse "/etc/shadow";
    const shadow_file = b.option([]const u8, "shadow", "expected path to the shadow file") orelse if (builtin.is_test) "./shadow" else "/etc/shadow";
    opts.addOption([]const u8, "shadow", shadow_file);

    const passwd_file = b.option([]const u8, "passwd", "expected path to the passwd file") orelse "/etc/passwd";
    opts.addOption([]const u8, "passwd", passwd_file);

    // main executable
    const exe = b.addExecutable(.{
        .name = "doaz",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // .linkage = .static,
    });
    exe.root_module.addOptions("config", opts);

    // passwd module
    const passwd = b.addModule("passwd", .{
        .root_source_file = b.path("src/passwd.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    passwd.addOptions("config", opts);
    exe.root_module.addImport("passwd", passwd);

    exe.linkLibC();
    exe.linkSystemLibrary("crypt");
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

    const auth_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/auth.zig"),
        .target = target,
        .optimize = optimize,
    });
    auth_unit_tests.linkLibC();
    auth_unit_tests.linkSystemLibrary("crypt");

    // const spnam_unit_tests = b.addTest(.{
    //     .root_source_file = b.path("src/passwd/getspnam.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // spnam_unit_tests.root_module.addOptions("config", opts);
    // spnam_unit_tests.linkLibC();

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const run_id_unit_tests = b.addRunArtifact(id_unit_tests);
    const test_id_unit_tests = b.addRunArtifact(auth_unit_tests);
    // const run_spnam_unit_tests = b.addRunArtifact(spnam_unit_tests);

    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_id_unit_tests.step);
    test_step.dependOn(&test_id_unit_tests.step);
    // test_step.dependOn(&run_spnam_unit_tests.step);
}
