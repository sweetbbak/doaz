const std = @import("std");
const user = @import("id.zig");
const uid_t = @import("std").c.uid_t;
const gid_t = @import("std").c.gid_t;

pub fn main() !void {
    // const my_name = "sweet";
    const safepath = "/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin";

    // const my_pass = user.getpwuid(uid);
    const target_pass = user.getpwuid(0);

    // if (std.os.linux.getuid() != 0)
    //     std.log.err("binary is not setuid", .{});

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

    const env_map = try arena.allocator().create(std.process.EnvMap);
    env_map.* = try std.process.getEnvMap(arena.allocator());
    defer env_map.deinit(); // technically unnecessary when using ArenaAllocator
                            
    // maybe this?
    // const ui = try std.process.posixGetUserInfo("sweet");

    // set env
    try env_map.put("PATH", safepath);

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
