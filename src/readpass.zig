const std = @import("std");
const builtin = @import("builtin");
const posix = @import("std").posix;
const Allocator = @import("std").mem.Allocator;

const Term = @This();

/// tty termios
termios: posix.termios,
/// The file descriptor of the tty
fd: posix.fd_t,

pub const SignalHandler = struct {
    context: *anyopaque,
    callback: *const fn (context: *anyopaque) void,
};

// empty sigaction to save the old ones in
var save_winch: posix.Sigaction = undefined;
var save_hup:  posix.Sigaction = undefined;
var save_alarm: posix.Sigaction = undefined;
var save_pipe: posix.Sigaction = undefined;
var save_quit: posix.Sigaction = undefined;
var save_term: posix.Sigaction = undefined;
var save_ttin: posix.Sigaction = undefined;
var save_ttout: posix.Sigaction = undefined;

// save sent signals for later
var GOT_SIG: c_int = 0;

pub fn init() !Term {
    // Open our tty
    const fd = try posix.open("/dev/tty", .{ .ACCMODE = .RDWR }, 0);

    // Set the termios of the tty
    const termios = try posix.tcgetattr(fd);

    var act = posix.Sigaction{
        .handler = .{ .handler = Term.handler },
        .mask = posix.empty_sigset,
        .flags = 0,
    };

    // save and restore these
    posix.sigaction(posix.SIG.WINCH, &act, &save_winch);
    posix.sigaction(posix.SIG.HUP, &act, &save_hup);
    posix.sigaction(posix.SIG.ALRM, &act, &save_alarm);
    posix.sigaction(posix.SIG.PIPE, &act, &save_pipe);
    posix.sigaction(posix.SIG.QUIT, &act, &save_quit);
    posix.sigaction(posix.SIG.TERM, &act, &save_term);
    posix.sigaction(posix.SIG.TTIN, &act, &save_ttin);
    posix.sigaction(posix.SIG.TTOU, &act, &save_ttout);
    // posix.sigaction(posix.SIG.INT, &act, null); // we want to interrupt
    // posix.sigaction(posix.SIG.STOP, &act, null); // idk why this causes a segfault

    const self: Term = .{
        .fd = fd,
        .termios = termios,
    };

    return self;
}

pub fn deinit() void {
    // restore old handlers
    posix.sigaction(posix.SIG.WINCH, &save_winch, null);
    posix.sigaction(posix.SIG.HUP, &save_hup, null);
    posix.sigaction(posix.SIG.ALRM, &save_alarm, null);
    posix.sigaction(posix.SIG.PIPE, &save_pipe, null);
    posix.sigaction(posix.SIG.QUIT, &save_quit, null);
    posix.sigaction(posix.SIG.TERM, &save_term, null);
    posix.sigaction(posix.SIG.TTIN, &save_ttin, null);
    posix.sigaction(posix.SIG.TTOU, &save_ttout, null);

    const pid = std.os.linux.getpid();
    _ = std.os.linux.kill(pid, GOT_SIG);
}

pub fn handler(sig: c_int) callconv(.C) void {
    std.log.debug("signal: {d}", .{sig});
    GOT_SIG = sig;
}

pub fn read(self: *const Term, buf: []u8) !usize {
    return posix.read(self.fd, buf);
}

pub fn opaqueRead(ptr: *const anyopaque, buf: []u8) !usize {
    const self: *const Term = @ptrCast(@alignCast(ptr));
    return posix.read(self.fd, buf);
}

pub fn anyReader(self: *const Term) std.io.AnyReader {
    return .{
        .context = self,
        .readFn = Term.opaqueRead,
    };
}

/// turn off terminal echo and read a password into the given buffer
pub fn readpass(self: *const Term, buf: []u8) !usize {
    // get the default terminal state
    const state = try posix.tcgetattr(self.fd);
    var raw = state;

    // raw.iflag.ICRNL = false;
    raw.lflag.ECHO = false;
    // raw.lflag.ICANON = false;
    // raw.lflag.ISIG = false;

    // set state to no echo
    try posix.tcsetattr(self.fd, .FLUSH, raw);

    // return the terminal state to normal
    defer {
        posix.tcsetattr(self.fd, .FLUSH, state) catch |err| {
            std.log.err("couldnt reset terminal: {s}", .{@errorName(err)});
        };
    }

    return try self.readline(buf);
}

fn echo(self: *const Term, buf: []const u8) !void {
    const state = try posix.tcgetattr(self.fd);
    try posix.tcsetattr(self.fd, .FLUSH, self.termios);
    std.debug.print("{s}", .{buf});
    try posix.tcsetattr(self.fd, .FLUSH, state);
}

fn readline(self: *const Term, buf: []u8) !usize {
    if (buf.len == 0) {
        return error.BufferLengthInvalid;
    }

    const reader = self.anyReader();
    var fbs = std.io.fixedBufferStream(buf);
    const writer = fbs.writer();

    const max_size = fbs.buffer.len;

    for (0..max_size) |_| {
        const byte: u8 = try reader.readByte();
        if (byte == '\n' or byte == '\r') return fbs.pos;
        try writer.writeByte(byte);
    }

    return error.StreamTooLong;
}

/// read a password into the given buffer and returns
/// a pointer casted slice of that same buffer that contains
/// the input
pub fn getpassZ(rbuf: []u8) ![*:0]const u8 {
    const term = try init();
    defer deinit();

    const buf = try term.readpass(rbuf);
    const pass: [*:0]const u8 = @ptrCast(rbuf[0..buf]);
    return pass;
}

/// read a password into the given buffer and returns
/// a pointer casted slice of that same buffer that contains
/// the input
pub fn getpass(rbuf: []u8) ![]const u8 {
    const term = try init();
    defer deinit();

    const buf = try term.readpass(rbuf);
    return rbuf[0..buf];
}
