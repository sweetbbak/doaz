const std = @import("std");
const user = @import("id.zig");
const pass = @import("getpw.zig");
const getopt = @import("getopt.zig");
const linux = std.os.linux;
const log = std.log;

const exit = std.posix.exit;
const span = std.mem.span;
const eql = std.mem.eql;

const uid_t = @import("std").c.uid_t;
const gid_t = @import("std").c.gid_t;
const passwd = std.c.passwd;
