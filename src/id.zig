const std = @import("std");
const tty = @import("tty.zig");
const auth = @import("auth.zig");
const rpass = @import("readpass.zig");

const mem = std.mem;
const span = std.mem.span;
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const linux = std.os.linux;
const posix = std.posix;
const uid_t = std.c.uid_t;
const gid_t = std.c.gid_t;
const passwd = std.c.passwd;

const c = @cImport({
    @cInclude("pwd.h");
    @cInclude("grp.h");
    @cInclude("unistd.h");
    @cInclude("string.h");
});

const shadow = @cImport({
    @cInclude("shadow.h");
});

const crypt = @cImport({
    @cInclude("crypt.h");
});

const IdentityError = error{
    UIDMismatch,
    NoPasswd,
    InvalidGID,
    GroupListFail,
    InitGroupFail,
    Getpwnam,
    GetShadowEntry,
};

const AuthError = error{InvalidPassword};

fn ErrorMessage(err: anyerror) []const u8 {
    switch (err) {
        error.UIDMismatch => {
            return "UID and expected UID do not match";
        },
        error.NoPasswd => {
            return "attempted to access null passwd field";
        },
        else => {
            return "undefined";
        },
    }
}

const NGROUPS_MAX = 65536; // 32 prior to linux 2.4.*

/// takes an allocator and a username... returns a list of group names
/// remember to free each individual item in the resulting list or otherwise
/// it will leak.
pub fn getgroups(allocator: Allocator, name: [*:0]const u8) ![][]const u8 {
    var groups_names = std.ArrayList([]const u8).init(allocator);
    errdefer groups_names.deinit();

    var ngroups: i32 = NGROUPS_MAX;
    var groups_gids: [NGROUPS_MAX]gid_t = undefined;

    if (std.c.getpwnam(name)) |pwd| {
        if (c.getgrouplist(pwd.name.?, pwd.gid, &groups_gids, &ngroups) == -1) return error.GroupListFail;
    } else {
        return error.NoPasswd;
    }

    if (ngroups != -1) {
        var i: usize = 0;
        while (i < ngroups) : (i += 1) {
            const g = c.getgrgid(groups_gids[i]);
            if (g == null) {
                continue;
            }

            const gname = try allocator.dupe(u8, std.mem.span(g.*.gr_name));
            errdefer allocator.free(gname);
            try groups_names.append(gname);
        }
    }

    return groups_names.toOwnedSlice();
}

/// takes a user name, and returns their UID (name->UID)
pub fn parseuid(name: [*:0]const u8) !uid_t {
    if (std.c.getpwnam(name)) |passw| {
        return passw.uid;
    } else {
        return error.NoPasswd;
    }
}

pub fn uidcheck(name: [*:0]const u8, desired: uid_t) !void {
    const uid = try parseuid(name);
    if (uid == desired) return else return error.UIDMismatch;
}

pub fn parsegid(groupname: [*:0]const u8) !gid_t {
    var buf: [1024]u8 = undefined; // Buffer for `getgrnam_r`
    var grp: c.struct_group = undefined; // Struct to store the result
    var result: ?*c.struct_group = null; // Pointer to the result struct

    const ret = c.getgrnam_r(&groupname[0], &grp, &buf[0], buf.len, &result);

    if (ret != 0 or result == null) {
        return error.NullGID;
    }

    return grp.gr_gid;
}

pub fn getpwuid(uid: uid_t) !*passwd {
    if (std.c.getpwuid(uid)) |pass| {
        return pass;
    } else {
        return error.NullPasswd;
    }
}

pub extern "c" fn getpwuid_r(uid: uid_t, pw: *passwd, buf: [*]u8, buflen: usize, pwretp: ?*passwd) c_int;

pub fn getpwuid_rr(uid: uid_t, buf: []u8, pw: *passwd, result: ?*passwd) !*passwd {
    // var pw: passwd = undefined;
    // var result: ?*passwd = null;
    // const errno = std.c.getpwuid_r(uid, &pw, @ptrCast(buf), buf.len, &result);
    const errno = getpwuid_r(uid, pw, @ptrCast(buf), buf.len, result);
    if (errno != 0) {
        const e = posix.errno(errno);
        std.log.debug("errno {s} exit {d}\n", .{ @tagName(e), errno });

        switch (e) {
            .NOENT, .SRCH, .BADF, .PERM => return error.EntryNotFound,
            .INTR => return error.Interrupt,
            .MFILE, .NFILE => return error.MaxFileLimit,
            .NOMEM => return error.MemoryError,
            .RANGE => return error.InsufficientBuffer,
            .IO => return error.InputOutputError,
            else => return if (result != null) return result.? else return error.IDK,
        }
    } else if (result == null) {
        return error.NullPasswd;
    } else {
        return result.?;
    }
}

// read the man page lmao it says calling this multiple times can and will
// overwrite prior calls to this function
pub fn getpwnam(name: [*:0]const u8) !*passwd {
    if (std.c.getpwnam(name)) |pass| {
        return pass;
    } else {
        return error.NullPasswd;
    }
}

pub fn getpwnam_r(name: [*:0]const u8, buf: []u8) !*passwd {
    const pw: *passwd = undefined;
    const result: *passwd = undefined;
    if (std.c.getpwnam_r(name, &pw, @ptrCast(buf), buf.len, &result)) |pass| {
        return pass;
    } else {
        return error.NullPasswd;
    }
}

/// passwd can be overwritten when called multiple times, this ensures
/// that you own the memory and a lasting copy of the passwd entry
// pub fn getpwuid_alloc(alloc: Allocator, uid: uid_t) !*passwd {
//     _ = alloc; // autofix
//     if (std.c.getpwuid(uid)) |pass| {
//         const p: passwd = undefined;
//         @memcpy(p, pass);
//         return p;
//     } else {
//         return error.NullPasswd;
//     }
// }

// read the man page lmao it says calling this multiple times can and will
// overwrite prior calls to this function
/// passwd can be overwritten when called multiple times, this ensures
/// that you own the memory and a lasting copy of the passwd entry
pub fn getpwnam_alloc(alloc: Allocator, name: [*:0]const u8) !*passwd {
    if (std.c.getpwnam(name)) |pass| {
        return try alloc.dupe(pass);
    } else {
        return error.NullPasswd;
    }
}

/// fills the resulting spwd struct with the relevant information
pub fn getspnam_r(name: [*:0]const u8, buf: []u8, pw: *shadow.spwd, result: ?*shadow.spwd) !void {
    // const spwd: ?*shadow.spwd = shadow.getspnam(name);
    const ret = shadow.getspnam_r(name, result, @ptrCast(buf), buf.len, @ptrCast(pw));
    switch (ret) {
        0 => return,
        -1 => return error.SpwdError,
        else => return error.SpwdUnkownError,
    }
}

/// authorize the given user, if an error is returned,
/// the user is not authorized
// pub fn shadowauth(name: [*:0]const u8, persist: bool) !void {
pub fn shadowauth(pw: *passwd, persist: bool) !void {
    if (persist) {}

    // const pw = getpwnam(name) catch |err| {
    //     std.log.err("getpwnam {s}", .{@errorName(err)});
    //     return error.Getpwnam;
    // };

    var hash: [*:0]const u8 = pw.passwd orelse {
        std.log.err("getpwnam", .{});
        return error.Getpwnam;
    };

    const name = pw.name.?;
    std.log.debug("hash {s} name {s}", .{ hash, name });

    if (hash[0] == 'x' and hash[1] == '\x00') {
        const spwd: ?*shadow.spwd = shadow.getspnam(name);

        // var buffer: [1024]u8 = undefined;
        // var tmp: shadow.spwd = undefined;
        // var spwd: shadow.spwd = undefined;
        // try getspnam_r(name, &buffer, &tmp, &spwd);
        // try getspnam_r(name, &buffer, &spwd, &tmp);
        // std.log.debug("real: {any}\ntemp: {any}", .{spwd, tmp});

        // handle situations where passwd is unset ie second field is '!' or '!!' or otherwise
        // doas allows this to be done without auth I guess
        if (spwd) |sp| hash = sp.sp_pwdp else {
            // if (spwd.sp_pwdp) |sp| hash = sp.sp_pwdp else {
            std.log.err("Authentication failed: failed to get passwd entry for {s}", .{name});
            return error.GetShadowEntry;
        }
        // hash = spwd.sp_pwdp;
    } else if (hash[0] != '*') {
        std.log.err("Authentication failed: failed to get passwd entry, found '*' in hash", .{});
        return error.GetShadowEntry;
    }

    std.log.debug("hash {s}", .{hash});

    var bhost: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(@ptrCast(&bhost)) catch "?";

    var bprompt: [256]u8 = std.mem.zeroes([256]u8);

    if (std.posix.getenv("NO_COLOR")) |_| {
        _ = std.fmt.bufPrint(&bprompt, "\rdoaz ({s}@{s}) password: ", .{ name, hostname }) catch unreachable;
    } else {
        _ = std.fmt.bufPrint(&bprompt, "\r{s}doaz ({s}{s}{s}{s}{s}@{s}{s}{s}{s}{s}) password:{s} ", .{
            "\x1b[90m",
            "\x1b[0m",
            "\x1b[32m",
            name,
            "\x1b[0m",
            "\x1b[90m",
            "\x1b[0m",
            "\x1b[34m",
            hostname,
            "\x1b[0m",
            "\x1b[90m",
            "\x1b[0m",
        }) catch unreachable;
    }

    // print the prompt
    std.debug.print("{s}", .{bprompt});
    defer std.debug.print("\r\x1b[2K", .{});

    // password buffer. must be cleared as soon as possible.
    var rbuf: [1024]u8 = std.mem.zeroes([1024]u8);
    defer {
        mem.doNotOptimizeAway(.{
            @memset(&rbuf, 0),
        });
    }

    const pass = try rpass.getpass(&rbuf);

    try auth.authorizeZ(pass, hash);
    return;
}

pub fn initgroups(user: [*c]const u8, group: gid_t) !void {
    if (c.initgroups(user, group) != 0) return error.GroupListFail else return;
}

test "get group names" {
    const alloc = std.testing.allocator;

    if (std.posix.getenv("USER")) |user| {
        const groups = try getgroups(alloc, user);
        assert(groups.len != 0);
        try std.testing.expect(groups.len != 0);

        // we have to do the "reverse" of how we allocated this function
        defer {
            for (groups) |g| alloc.free(g);
            alloc.free(groups);
        }

        std.debug.print("\n", .{});

        var i: usize = 0;
        while (i < groups.len) : (i += 1) {
            std.debug.print("{s}\n", .{groups[i]});
        }
    } else {
        std.log.err("unable to test getgroups() USER env var is null", .{});
    }
}
