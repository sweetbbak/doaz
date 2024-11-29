const std = @import("std");
const builtin = @import("builtin");
const posix = @import("std").posix;
const Allocator = @import("std").mem.Allocator;

const Term = @This();

termios: posix.termios,
/// The file descriptor of the tty
fd: posix.fd_t,

pub const SignalHandler = struct {
    context: *anyopaque,
    callback: *const fn (context: *anyopaque) void,
};

/// global signal handlers
var handlers: [8]SignalHandler = undefined;
var handler_mutex: std.Thread.Mutex = .{};
var handler_idx: usize = 0;

var handler_installed: bool = false;

/// initializes a Tty instance by opening /dev/tty and "making it raw". A
/// signal handler is installed for SIGWINCH. No callbacks are installed, be
/// sure to register a callback when initializing the event loop
pub fn init() !Term {
    // Open our tty
    const fd = try posix.open("/dev/tty", .{ .ACCMODE = .RDWR }, 0);

    // Set the termios of the tty
    const termios = try posix.tcgetattr(fd);

    var act = posix.Sigaction{
        .handler = .{ .handler = Term.handleWinch },
        .mask = posix.empty_sigset,
        .flags = 0,
    };

    posix.sigaction(posix.SIG.WINCH, &act, null);
    handler_installed = true;

    const self: Term = .{
        .fd = fd,
        .termios = termios,
    };

    return self;
}

/// turn off terminal echo and read a password into the given buffer
pub fn readpass(self: *const Term, buf: []u8) !usize {
    // get the default terminal state
    const state = try posix.tcgetattr(self.fd);
    var raw = state;

    // raw.iflag.ICRNL = false;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;

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

/// read into the given buffer and return the index of what has been read...
/// be careful not to slice this data, it needs to be a null terminated
/// array to be passed to crypt() - otherwise you will have odd errors
fn readline(self: *const Term, buf: []u8) !usize {
    const reader = self.anyReader();
    var fbs = std.io.fixedBufferStream(buf);
    try reader.streamUntilDelimiter(fbs.writer(), '\n', fbs.buffer.len);
    return fbs.pos;
}

fn handleWinch(_: c_int) callconv(.C) void {
    handler_mutex.lock();
    defer handler_mutex.unlock();
    var i: usize = 0;
    while (i < handler_idx) : (i += 1) {
        const handler = handlers[i];
        handler.callback(handler.context);
    }
}

/// makeRaw enters the raw state for the terminal.
pub fn makeRaw(fd: posix.fd_t) !posix.termios {
    const state = try posix.tcgetattr(fd);
    var raw = state;
    // see termios(3)
    raw.iflag.IGNBRK = false;
    raw.iflag.BRKINT = false;
    raw.iflag.PARMRK = false;
    raw.iflag.ISTRIP = false;
    raw.iflag.INLCR = false;
    raw.iflag.IGNCR = false;
    raw.iflag.ICRNL = false;
    raw.iflag.IXON = false;

    raw.oflag.OPOST = false;

    raw.lflag.ECHO = false;
    raw.lflag.ECHONL = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;

    raw.cflag.CSIZE = .CS8;
    raw.cflag.PARENB = false;

    raw.cc[@intFromEnum(posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(posix.V.TIME)] = 0;
    try posix.tcsetattr(fd, .FLUSH, raw);
    return state;
}
