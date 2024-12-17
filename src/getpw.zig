const std = @import("std");
const mem = std.mem;
const log = std.log;
const fs = @import("fs.zig");
const builtin = @import("builtin");
const config = @import("config");

const uid_t = std.c.uid_t;
const gid_t = std.c.gid_t;

pub const PASSWD = "/etc/passwd";

pub const shadow_entry = enum {
    name,
    passwd,
    uid,
    gid,
    gecos,
    dir,
    shell,
};

pub const passwd = struct {
    name: ?[:0]const u8, // username
    passwd: ?[:0]const u8, // user password
    uid: uid_t, // user ID
    gid: gid_t, // group ID
    gecos: ?[:0]const u8, // user information
    dir: ?[:0]const u8, // home directory
    shell: ?[:0]const u8, // shell program
};

pub fn xatol(s: []const u8) u32 {
    return std.fmt.parseInt(u32, s, 10) catch 0;
}

fn parsepass(s: []const u8, pass: *passwd) !void {
    var it = mem.splitScalar(u8, s, ':');
    var i: u8 = 0;
    while (it.next()) |value| {
        defer i += 1;
        // std.debug.print("value: {s}\n", .{value});

        // redundant but whatever
        if (value.len == 0 or mem.eql(u8, value, "")) {
            log.debug("{d}: empty entry\n", .{i});
            // std.debug.print("{d}: empty entry\n", .{i});
        } else {
            // std.debug.print("{d}: {s}\n", .{ i, value });
            log.debug("{d}: {s}\n", .{ i, value });
        }

        const entry_type: shadow_entry = @enumFromInt(i);
        // std.debug.print("{d}: {any}\n", .{ i, entry_type });

        switch (entry_type) {
            .name => {
                pass.*.name = @ptrCast(value);
            },
            .passwd => {
                pass.*.passwd = @ptrCast(value);
            },
            .uid => {
                pass.*.uid = xatol(value);
            },
            .gid => {
                pass.*.gid = xatol(value);
            },
            .gecos => {
                pass.*.gecos = @ptrCast(value);
            },
            .dir => {
                pass.*.dir = @ptrCast(value);
            },
            .shell => {
                pass.*.shell = @ptrCast(value);
            },
        }
    }
    printPass(pass);
}

pub fn getpwuid(uid: uid_t, sp: *passwd) !void {
    var buf: [1024 * 2]u8 = undefined;
    var it = try fs.readLines(config.passwd, &buf, .{ .open_flags = .{ .mode = .read_only } });
    while (try it.next()) |line| {

        std.log.debug("parsing passwd entry: {s}\n", .{line});
        // var temp: passwd = undefined;
        try parsepass(line, &sp);
        if (sp.uid == uid) {
            break;
        } else {
            sp = null;
        }
    }
}

pub fn getpwuid_test(uid: uid_t, sp: *passwd) !void {
    var buf: [1024 * 2]u8 = undefined;
    var it = try fs.readLines(PASSWD, &buf, .{ .open_flags = .{ .mode = .read_only } });
    while (try it.next()) |line| {

        std.log.debug("parsing passwd entry: {s}\n", .{line});
        // var temp: passwd = undefined;
        try parsepass(line, sp);
        if (sp.uid == uid) {
            break;
        }
    }
}

// consider using NSCD (name service cache daemon) socket for querying cached information
pub fn getpwnam(name: []const u8, sp: *passwd) !void {
    var buf: [1024 * 2]u8 = undefined;
    var it = try fs.readLines(config.passwd, &buf, .{ .open_flags = .{ .mode = .read_only } });
    while (try it.next()) |line| {
        if (!mem.eql(u8, name, line[0..name.len])) {
            continue;
        }

        std.log.debug("pass ent: {s}\n", .{line});
        try parsepass(line, sp);
    }
}

// consider using NSCD (name service cache daemon) socket for querying cached information
fn getpwnam_test(name: []const u8, sp: *passwd) !void {
    var buf: [1024 * 2]u8 = undefined;
    var it = try fs.readLines(PASSWD, &buf, .{ .open_flags = .{ .mode = .read_only } });
    while (try it.next()) |line| {
        if (!mem.eql(u8, name, line[0..name.len])) {
            continue;
        }

        std.log.debug("pass ent: {s}\n", .{line});
        try parsepass(line, sp);
    }
}

test "get passwd from name - getpwnam" {
    var pass: passwd = undefined;
    try getpwnam_test("sweet", &pass);
    printPass(&pass);
}

fn printPass(pass: *passwd) void {
    std.debug.print("-----------------\n", .{});
    std.debug.print("1: name {s}, ", .{pass.name.?});
    std.debug.print("2: passwd {s}, ", .{pass.passwd.?});
    std.debug.print("3: dir {s}, ", .{pass.dir.?});
    std.debug.print("4: gecos {s}, ", .{pass.gecos.?});
    std.debug.print("5: shell {s}, ", .{pass.shell.?});
    std.debug.print("6: gid {d}, 7: uid {d}", .{pass.gid, pass.uid});
    std.debug.print("\n-----------------\n", .{});
}

test "get passwd from uid - getpwuid" {
    var pass: passwd = undefined;
    try getpwuid_test(1000, &pass);
    printPass(&pass);
}
