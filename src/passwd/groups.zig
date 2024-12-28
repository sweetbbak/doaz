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
    passwd: []const u8,
    gid: gid_t,
};

pub const group_entry = enum {
    name,
    passwd,
    gid,
    users,
};

pub fn _getgroups(size: usize, list: ?*gid_t) usize {
    return linux.syscall2(.getgroups, size, @intFromPtr(list));
}

/// The getgroups function is used to inquire about the supplementary
/// group IDs of the process. Is POSIX compatible
pub fn getgroups(alloc: Allocator) ![]uid_t {
    // why cant I use null
    const ngroups: usize = _getgroups(0, null);
    if (ngroups <= 0) {
        return error.GetGroupsError;
    }

    std.debug.print("number of groups: {d}\n", .{ngroups});
    const groups_gids: []u32 = try alloc.alloc(u32, ngroups);

    const exit = _getgroups(ngroups, @ptrCast(groups_gids));
    if (exit < 0) {
        return error.GetGroupsError;
    }

    return groups_gids;
}

/// sets the supplementary group IDs for the calling process
/// (which can be different than the real GIDs from the calling user)
pub fn setgroups(count: usize, groups: []gid_t) !void {
    const exit = linux.setgroups(count, @ptrCast(groups));
    if (exit < 0) {
        return error.SetgroupsFail;
    }
}

pub fn atoi(s: []const u8) u32 {
    return std.fmt.parseInt(u32, s, 10) catch 0;
}

/// parse a group entry line, returns null if USER or GID is not in the entry
/// doesn't handle multi-line groups
fn parsegroups(s: []const u8, user: ?[]const u8, gid: gid_t) !?Group {
    var group: Group = undefined;
    var it = mem.splitScalar(u8, s, ':');
    var i: u8 = 0;

    while (it.next()) |value| {
        defer i += 1;
        const entry_type: group_entry = @enumFromInt(i);

        switch (entry_type) {
            .name => {
                group.name = value;
            },
            .passwd => {
                group.passwd = value;
            },
            .gid => {
                group.gid = atoi(value);
                if (gid == group.gid) {
                    return group;
                }
            },
            .users => {
                if (value.len == 0) {
                    continue;
                }

                // just going to skip returning the members of a group
                // for now, I dont think I need it and it makes things
                // complicated
                var user_iter = mem.splitScalar(u8, value, ',');

                while (user_iter.next()) |member| {
                    if (member.len == 0) {
                        continue;
                    }

                    if (user) |_user| {
                        if (mem.eql(u8, _user, member) or mem.eql(u8, _user, group.name)) {
                            return group;
                        }
                    }
                }
            },
        }
    }
    return null;
}

/// get a group list for the given user
/// caller must free memory
pub fn getgrouplist(alloc: Allocator, user: ?[]const u8, gid: gid_t) ![]Group {
    var buf: [1024 * 2]u8 = undefined;
    var it = try fs.readLines(GROUPS, &buf, .{ .open_flags = .{ .mode = .read_only } });
    var groups = std.ArrayList(Group).init(alloc);

    while (try it.next()) |line| {
        const grp = try parsegroups(line, user, gid);
        if (grp) |group| {
            try groups.append(group);
        }
    }
    return groups.toOwnedSlice();
}

/// get a grouplist for the given user and set the
/// supplementary group list to that grouplist
pub fn initgroups(allocator: Allocator, user: []const u8, gid: gid_t) !void {
    const groups = try getgrouplist(allocator, user, gid);
    defer allocator.free(groups);

    const gids: []gid_t = try allocator.alloc(gid_t, groups.len);
    defer allocator.free(gids);

    for (groups, 0..) |group, i| {
        gids[i] = group.gid;
    }

    try setgroups(gids.len, gids);
}

/// get a name from a GID
fn getgrnam() !void {}

test "groups" {
    const alloc = std.testing.allocator;

    try initgroups(alloc, "sweet", 1000);

    const groups = try getgroups(alloc);
    defer alloc.free(groups);

    for (groups, 1..) |value, i| {
        std.debug.print("{d}: {d}\n", .{ i, value });
    }

    const _groups = try getgrouplist(alloc, "sweet", 1000);
    defer alloc.free(_groups);

    for (_groups) |value| {
        std.debug.print("{s} {d} {s}\n", .{ value.name, value.gid, value.passwd });
    }

    try setgroups(groups.len, groups);
    std.debug.print("\n", .{});
}

test "fuzz initgroups" {
    const alloc = std.testing.allocator;
    const rand_gen = std.Random.DefaultPrng;
    // var rand = rand_gen.init(0);
    // var some_random_num = rand.random().int(u32);
    // std.debug.print("random number is {}", .{some_random_num});

    const global = struct {
        fn fuzzinitgroups(input: []const u8) anyerror!void {
            var rand = rand_gen.init(0);
            const some_random_num = rand.random().int(u32);
            try initgroups(alloc, input, some_random_num);
        }
    };
    try std.testing.fuzz(global.fuzzinitgroups, .{});
    try initgroups(alloc, "sweet", 1000);
}
