const std = @import("std");
const user = @import("id.zig");
const uid_t = @import("std").c.uid_t;
const gid_t = @import("std").c.gid_t;

pub fn main() !void {
    // const my_name = "sweet";
    const safepath = "/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin";

    // const my_pass = user.getpwuid(uid);
    const target_pass = user.getpwuid(0);

    if (std.os.linux.geteuid() != 0)
        std.log.err("binary is not setuid", .{});

    var formerpath: [:0]const u8 = undefined;
    if (std.posix.getenv("PATH")) |path| {
        formerpath = path;
    } else {
        formerpath = "";
    }

    // root
    // const target: uid_t = 0;
    // user.getpwuid(target);

    // set real and effective group ID
    try std.posix.setregid(target_pass.?.gid, target_pass.?.gid);

    // try user.initgroups(target_pass.?.name, target_pass.?.gid);

    // set real and effective user ID
    try std.posix.setreuid(target_pass.?.uid, target_pass.?.uid);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var env_map = try arena.allocator().create(std.process.EnvMap);
    env_map.* = try std.process.getEnvMap(arena.allocator());
    defer env_map.deinit(); // technically unnecessary when using ArenaAllocator
                            
    // maybe this?
    // const ui = try std.process.posixGetUserInfo("sweet");

    var enviter = env_map.iterator();

    while (enviter.next()) |value| {
        const eql = std.mem.eql;
        const key = value.key_ptr.*;
        if (eql(u8, "TERM", key) or eql(u8, "DISPLAY", key)) {
            continue;
        } else {
            env_map.remove(key);
        }
    }

    // set env
    // TODO: check if these are null properly
    const span = std.mem.span;
    try env_map.put("PATH", safepath);
    try env_map.put("HOME", span(target_pass.?.dir.?));
    try env_map.put("USER", span(target_pass.?.name.?));
    try env_map.put("LOGNAME", span(target_pass.?.name.?));
    try env_map.put("DOAS_USER", span(target_pass.?.name.?));
    try env_map.put("SHELL", span(target_pass.?.shell.?));

    const calloc = std.heap.c_allocator;
    var args = std.process.args();
    defer args.deinit();

    // skip self / exe
    _ = args.next();

    var arglist = std.ArrayList([]const u8).init(calloc);
    errdefer arglist.deinit();

    while (args.next()) |value| {
        try arglist.append(value);
    }

    const argv = try arglist.toOwnedSlice();

    std.process.execve(calloc, argv, env_map) catch unreachable;
}
