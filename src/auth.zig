const std = @import("std");
const mem = @import("std").mem;
const span = @import("std").mem.span;

const c = @cImport({
    @cInclude("pwd.h");
    @cInclude("grp.h");
    @cInclude("unistd.h");
    @cInclude("string.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
});

const shadow = @cImport({
    @cInclude("shadow.h");
});

const crypt = @cImport({
    @cInclude("crypt.h");
});

const Auth = error{
    NullPasswd,
    CryptError,
    IncorrectPassword,
};

pub fn eqlZ(s1: [*:0]const u8, s2: [*:0]const u8) bool {
    var p1 = s1;
    var p2 = s2;
    while (p1[0] != 0 and p1[0] == p2[0]) {
        p1 += 1;
        p2 += 1;
    }
    return p1[0] == p2[0];
}

/// check a password against a given hash (c strings)
pub fn authorizeZ(response: [*:0]const u8, hash: [*:0]const u8) !void {
    const encrypted: [*c]u8 = crypt.crypt(response, hash) orelse {
        return error.CryptError;
    };

    if (std.mem.orderZ(u8, encrypted, hash) != .eq) {
        return error.IncorrectPassword;
    }

    std.log.debug("success!", .{});
}

/// check a password against a given hash
pub fn authorize(input: []const u8, passhash: []const u8) !void {
    const response: [*:0]const u8 = @ptrCast(input);
    const hash: [*:0]const u8 = @ptrCast(passhash);

    const encrypted: [*c]u8 = crypt.crypt(response, hash) orelse {
        return error.CryptError;
    };

    if (std.mem.orderZ(u8, encrypted, hash) != .eq) {
        return error.IncorrectPassword;
    }

    // std.log.debug("success! {s} {s}", .{ std.mem.span(encrypted), passhash });
}

// generated with:
// mkpasswd --method=yescrypt --stdin
// openssl passwd -6 -salt xyz yourpass
test "crypt" {
    const hash = "$6$xyz$VKswtvLoVpOLcpjDMIFXhxa8ukqqKSKHjcPBLZUk9NxWldmlFQY4stUGo.QjEhav7mp86ih2PRqYPqjkhWi5y.";
    const response = "yourpass";
    try authorize(response, hash);
    try authorizeZ(response, hash);

    const hash1 = "$6$xyz$VKswtvLoVpOLcpjDMIFXhxa8ukqqKSKHjcPBLZUk9NxWldmlFQY4stUGo.QjEhav7mp86ih2PRqYPqjkhWi5y.";
    const response1 = "yourpass";
    try authorize(response1, hash1);
    try authorizeZ(response1, hash1);

    const hash2 = "$5$xyz$bFmRmxEsxANNSk6Dfayq5MzdX6WNU5U9RXsCjqaRw/7";
    const response2 = "doaz";
    try authorize(response2, hash2);
    try authorizeZ(response2, hash2);

    const hash3 = "$y$j9T$NogOpCni90xg5Nc3kdtfS/$Ul/4PhlJ53JVhQ3Kf4FYik1ACBae6ZM2FSRwRU66cz7";
    const response3 = "doaz";
    try authorize(response3, hash3);
    try authorizeZ(response3, hash3);
}
