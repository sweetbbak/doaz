const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const linux = @import("std").os.linux;
const uid_t = @import("std").c.uid_t;
const gid_t = @import("std").c.gid_t;
const passwd = @import("std").c.passwd;

const c = @cImport({
    @cInclude("pwd.h");
    @cInclude("grp.h");
    @cInclude("unistd.h");
});

const shadow = @cImport({
    @cInclude("shadow.h");
});

const crypt = @cImport({
    @cInclude("crypt.h");
});

const bsd = @cImport({
    @cInclude("bsd/readpassphrase.h");
});

const IdentityError = error{
    UIDMismatch,
    NoPasswd,
    InvalidGID,
    GroupListFail,
    InitGroupFail,
};

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

pub fn getpwuid(uid: uid_t) ?*passwd {
    return std.c.getpwuid(uid);
}

pub fn getpnam(name: [*:0]const u8) ?*passwd {
    return std.c.getpwnam(name);
}

pub fn shadowauth(name: [*:0]const u8, persist: bool) bool {
    if (persist) {}

    const pw = std.c.getpwnam(@ptrCast(name.ptr)) orelse {
        std.log.err("getpwnam", .{});
        return false;
    };

    var hash: [*:0]const u8 = pw.pw_passwd orelse {
        std.log.err("getpwnam", .{});
        return false;
    };

    if (hash[0] == 'x' and hash[1] == '\x00') {
        // const spw = std.c.getpwnam_shadow(@ptrCast(name.ptr));
        const spwd: ?*shadow.spwd = shadow.getspnam(@ptrCast(name.ptr));

        if (spwd) |sp| hash = sp.sp_pwdp else {
            std.log.err("Authentication failed", .{});
        }
    } else if (hash[0] != '*') {
        std.log.err("Authentication failed", .{});
        return false;
    }

    var bhost: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(@ptrCast(&bhost)) catch "?";

    var bprompt: [256]u8 = std.mem.zeroes([256]u8);
    _ = std.fmt.bufPrint(&bprompt, "\rsaka ({s}@{s}) password: ", .{ name, hostname }) catch unreachable;

    var rbuf: [1024]u8 = undefined;
    defer @memset(&rbuf, 0); // TODO: make sure this is not optimized away

    const response: [*:0]const u8 = bsd.readpassphrase(@ptrCast(&bprompt), @ptrCast(&rbuf), 1024, bsd.RPP_REQUIRE_TTY) orelse {
        if (std.c._errno().* == @intFromEnum(std.posix.E.NOTTY)) {
            // LOG_AUTHPRIV | LOG_NOTICE,
            std.c.syslog((@as(c_int, 10) << @intCast(3)) | @as(c_int, 5), "tty required for %s", name.ptr);
            std.log.err("a tty is required", .{});
            return false;
        } else {
            std.log.err("readpassphrase", .{});
            return false;
        }
    };

    const encrypted: [*:0]u8 = crypt.crypt(response, hash) orelse {
        std.log.err("Authentication failed", .{});
        return false;
    };

    if (std.mem.orderZ(u8, encrypted, hash) == .eq) {
        // LOG_AUTHPRIV | LOG_NOTICE,
        std.c.syslog((@as(c_int, 10) << @intCast(3)) | @as(c_int, 5), "failed auth for %s", name.ptr);
        std.log.err("Authentication failed", .{});
        return false;
    }

    return true;
}

pub fn initgroups(user: [*c]const u8, group: gid_t) !void {
    if (c.initgroups(user, group) != 0) return error.GroupListFail else return;
}

test "get group names" {
    const alloc = std.testing.allocator;

    const groups = try getgroups(alloc, "sweet");

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

    // try std.testing.checkAllAllocationFailures(alloc, getgroups, .{"sweet"});
}
