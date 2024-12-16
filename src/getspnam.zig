const std = @import("std");
const uid_t = std.c.uid_t;
const gid_t = std.c.gid_t;

pub const spwd = struct {
    sp_namp: []const u8,
    sp_pwdp: []const u8,
    sp_lstchg: u32,
    sp_min: u32,
    sp_max: u32,
    sp_warn: u32,
    sp_inact: u32,
    sp_expire: u32,
    sp_flag: u32,
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

pub fn xatol(s: []const u8) !u8 {
    if (s.len < 1) {
        return error.Invalid;
    }

    if (s[0] == ':' or s[0] == '\n') {
        return error.Invalid;
    }

    return try std.fmt.parseInt(usize, s, 10);
}

fn parsespent() !u8 {}
