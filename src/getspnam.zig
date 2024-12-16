const std = @import("std");
const mem = std.mem;
const fs = @import("fs.zig");

const uid_t = std.c.uid_t;
const gid_t = std.c.gid_t;

pub const SHADOW = "/etc/shadow";

// default unknown values are -1
pub const spwd = struct {
    sp_namp: [:0]const u8, // user login name
    sp_pwdp: [:0]const u8, // encrypted password
    sp_lstchg: i32, // last password change
    sp_min: i32, // days until change allowed.
    sp_max: i32, // days before change required
    sp_warn: i32, // days warning for expiration
    sp_inact: i32, // days before account inactive
    sp_expire: i32, // date when account expires
    sp_flag: i32, // reserved for future use
};

pub const shadow_entry = enum {
    sp_namp,
    sp_pwdp,
    sp_lstchg,
    sp_min,
    sp_max,
    sp_warn,
    sp_inact,
    sp_expire,
    sp_flag,
};

pub const passwd = struct {
    name: ?[*:0]const u8, // username
    passwd: ?[*:0]const u8, // user password
    uid: uid_t, // user ID
    gid: gid_t, // group ID
    gecos: ?[*:0]const u8, // user information
    dir: ?[*:0]const u8, // home directory
    shell: ?[*:0]const u8, // shell program
};

pub fn xatol(s: []const u8) i32 {
    if (s.len < 1) {
        return -1;
    }

    if (s[0] == ':' or s[0] == '\n') {
        return -1;
    }

    const ret = std.fmt.parseInt(i32, s, 10) catch -1;
    return ret;
}

fn parsespent(s: []const u8, sp: *spwd) !void {
    var it = mem.splitScalar(u8, s, ':');
    var i: u8 = 0;
    while (it.next()) |value| {
        defer i += 1;

        // redundant but whatever
        if (value.len == 0 or mem.eql(u8, value, "")) {
            std.debug.print("{d}: empty entry\n", .{i});
        } else {
            std.debug.print("{d}: {s}\n", .{ i, value });
        }

        const entry_type: shadow_entry = @enumFromInt(i);
        std.debug.print("{d}: {any}\n", .{ i, entry_type });

        switch (entry_type) {
            .sp_namp => {
                sp.*.sp_namp = @ptrCast(value);
            },
            .sp_pwdp => {
                sp.*.sp_pwdp = @ptrCast(value);
            },
            .sp_lstchg => {
                sp.*.sp_lstchg = xatol(value);
            },
            .sp_min => {
                sp.*.sp_min = xatol(value);
            },
            .sp_max => {
                sp.*.sp_max = xatol(value);
            },
            .sp_warn => {
                sp.*.sp_warn = xatol(value);
            },
            .sp_inact => {
                sp.*.sp_inact = xatol(value);
            },
            .sp_expire => {
                sp.*.sp_expire = xatol(value);
            },
            .sp_flag => {
                sp.*.sp_flag = xatol(value);
            },
        }
    }
}

pub fn getspnam_r(name: []const u8, sp: *spwd) !void {
    var buf: [1024 * 2]u8 = undefined;
    // [TODO] change this to posix open with O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC
    // and allow this to be a configurable file location
    var it = try fs.readLines("/etc/shadow", &buf, .{ .open_flags = .{ .mode = .read_only } });
    while (try it.next()) |line| {
        if (!mem.eql(u8, name, line[0..name.len])) {
            continue;
        }

        std.debug.print("pass ent: {s}\n", .{line});
        try parsespent(name, sp);
    }
}

pub fn getspnam_r_test(name: []const u8, sp: *spwd) !void {
    var buf: [1024 * 2]u8 = undefined;
    // [TODO] change this to posix open with O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC
    var it = try fs.readLines("./shadow", &buf, .{ .open_flags = .{ .mode = .read_only } });
    while (try it.next()) |line| {
        if (!mem.eql(u8, name, line[0..name.len])) {
            continue;
        }

        std.debug.print("pass ent: {s}\n", .{line});
        try parsespent(name, sp);
    }
}

test "getspnam_r spoof" {
    var sp: spwd = undefined;
    try getspnam_r_test("sweet", &sp);
}

test "parse spwd entry" {
    var sp: spwd = undefined;
    try parsespent("sweet:$y$j9T$HzjVBclwrjI59QzzZkkY40$HNR.ah.x2Vlz0FlNIsEedpuDu51C4wqvHYn2LuLwqd4:19949:0:99999:7:::", &sp);

    std.debug.print("namp {s}\n", .{sp.sp_namp});
    std.debug.print("pwdp {s}\n", .{sp.sp_pwdp});
    std.debug.print("{any}\n", .{sp});
}
