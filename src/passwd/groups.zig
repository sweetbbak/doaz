const std = @import("std");
const fs = @import("fs.zig");
const builtin = @import("builtin");
const assert = std.debug.assert;
const config = @import("config");
const mem = std.mem;
const log = std.log;
const linux = std.os.linux;
const Allocator = std.mem.Allocator;
const uid_t = std.c.uid_t;
const gid_t = std.c.gid_t;

// pub const GROUPS = config.groups orelse "/etc/groups";
pub const GROUPS = "/etc/group";
const NGROUPS_MAX = 65536; // 32 prior to linux 2.4.*

pub const Group = struct {
    name: []const u8,
    passwd: ?[]const u8,
    gid: gid_t,
    user_list: ?[]const []const u8,
};

pub const group_entry = enum {
    name,
    passwd,
    gid,
    users,
};

/// The getgroups function is used to inquire about the supplementary
/// group IDs of the process. Is POSIX compatible
fn getgroups(alloc: Allocator) ![]uid_t {
    // why cant I use null
    var NULL: u32 = 0;
    const ngroups: usize = linux.getgroups(0, &NULL);
    if (ngroups <= 0) {
        return error.GetGroupsError;
    }

    const groups_gids: []u32 = try alloc.alloc(u32, ngroups);

    const exit = linux.getgroups(ngroups, @ptrCast(groups_gids));
    if (exit < 0) {
        return error.GetGroupsError;
    }

    return groups_gids;
}

/// sets the supplementary group IDs for the calling process
/// (which can be different than the real GIDs from the calling user)
fn setgroups(count: usize, groups: []gid_t) !void {
    const exit = linux.setgroups(count, @ptrCast(groups));
    if (exit < 0) {
        return error.SetgroupsFail;
    }
}

pub fn atoi(s: []const u8) u32 {
    return std.fmt.parseInt(u32, s, 10) catch 0;
}

fn parsegroups(alloc: Allocator, s: []const u8) !Group {
    var group: Group = undefined;
    var it = mem.splitScalar(u8, s, ':');
    var i: u8 = 0;

    while (it.next()) |value| {
        defer i += 1;

        // redundant but whatever
        if (value.len == 0 or mem.eql(u8, value, "")) {
            log.debug("{d}: empty entry\n", .{i});
            // std.debug.print("{d}: empty entry\n", .{i});
        } else {
            // std.debug.print("{d}: {s}\n", .{ i, value });
            log.debug("{d}: {s}\n", .{ i, value });
        }

        const entry_type: group_entry = @enumFromInt(i);
        // std.debug.print("{d}: {any}\n", .{ i, entry_type });

        switch (entry_type) {
            .name => {
                group.name = value;
            },
            .passwd => {
                group.passwd = value;
            },
            .gid => {
                group.gid = atoi(value);
            },
            .users => {
                if (value.len == 0) {
                    group.user_list = null;
                    continue;
                }

                var user_iter = mem.splitScalar(u8, value, ',');
                var user_names = std.ArrayList([]const u8).init(alloc);
                // defer user_names.deinit();

                while (user_iter.next()) |user| {
                    if (user.len == 0) {
                        continue;
                    }
                    try user_names.append(user);
                }
                group.user_list = try user_names.toOwnedSlice();
            },
        }
    }
    return group;
}

/// get a group list for the given user
fn getgrouplist(alloc: Allocator, name: []const u8) !void {
    var buf: [1024 * 2]u8 = undefined;
    var it = try fs.readLines(GROUPS, &buf, .{ .open_flags = .{ .mode = .read_only } });
    while (try it.next()) |line| {
        std.log.debug("group ent: {s}\n", .{line});

        const grp = try parsegroups(alloc, line);
        defer {
            if (grp.user_list) |list| {
                alloc.free(list);
            }
        }

        if (grp.user_list) |group_list| {
            // std.debug.print("name {s} - ", .{grp.name});
            // for (group_list) |uname| {
            //     std.debug.print("'{s}', ", .{uname});
            // }
            // std.debug.print("\n", .{});

            for (group_list) |uname| {
                if (mem.eql(u8, name, uname)) {
                    std.debug.print("{s} ", .{grp.name});
                } else if (mem.eql(u8, name, grp.name)) {
                    std.debug.print("{s} ", .{grp.name});
                }
            }
        }
    }
}

/// get a name from a GID
fn getgrnam() !void {}

// fn jk() usize {
//     return linux.syscall2(.getcwd, @intFromPtr(buf), size);
// }

test "groups" {
    const alloc = std.testing.allocator;
    const groups = try getgroups(alloc);
    defer alloc.free(groups);

    for (groups) |value| {
        std.debug.print("{d}\n", .{value});
    }

    try setgroups(groups.len, groups);
    std.debug.print("\n", .{});

    try getgrouplist(alloc, "sweet");
    std.debug.print("\n", .{});
}
