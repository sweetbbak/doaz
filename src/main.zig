const std = @import("std");
const user = @import("id.zig");
const getopt = @import("getopt.zig");
const linux = std.os.linux;
const log = std.log;

const exit = std.posix.exit;
const span = std.mem.span;
const eql = std.mem.eql;

const uid_t = @import("std").c.uid_t;
const gid_t = @import("std").c.gid_t;
const passwd = std.c.passwd;

fn usage() void {
    const message =
        \\usage: doaz [-Lns] [-C config] [-u user] command [args]
        \\execute a command as another user
        \\    -h     print this help message
        \\    -v     use verbose output
        \\    -u     execute the command as the given user
        \\    -s     execute the shell from $SHELL or /etc/passwd
        \\    -L     clear any persisted authentications
        \\    -n     non-interactive mode, fails if the matching rule doesnt have the nopass option
        \\    -C     parse and check the given configuration file and then exit
    ;
    std.debug.print("{s}\n", .{message});
}

pub fn main() !void {
    // if the binary hasn't been chmod'd as u+s and chowned as root
    // then we can't do anything
    if (std.os.linux.geteuid() != 0) {
        std.log.err("binary is not setuid", .{});
        exit(1);
    }

    const calloc = std.heap.c_allocator;

    // argument parsing values
    var target_name: ?[]const u8 = null;
    var config_path: ?[]const u8 = null;
    var run_shell: bool = false;
    var verbose: bool = false;
    var interactive: bool = true;

    // the flag -a exists in BSD for changing the login style
    var opts = getopt.getopt("C:nsu:hv");
    while (opts.next()) |maybe_opt| {
        if (maybe_opt) |opt| {
            switch (opt.opt) {
                'L' => {}, // implement persistent auth
                'u' => {
                    target_name = opt.arg.?;
                },
                'n' => interactive = false,
                's' => {
                    run_shell = true;
                },
                'C' => {
                    config_path = opt.arg.?;
                    break;
                },
                'v' => verbose = true,
                'h' => {
                    usage();
                    exit(0);
                },
                else => unreachable,
            }
        } else break;
    } else |err| {
        switch (err) {
            getopt.Error.InvalidOption => std.debug.print("invalid option: {c}\n", .{opts.optopt}),
            getopt.Error.MissingArgument => std.debug.print("option requires an argument: {c}\n", .{opts.optopt}),
        }
        exit(1);
    }

    // parse the config file for errors and exit (currently a no-op)
    if (config_path) |conf| {
        std.debug.print("checking config file: '{s}'\n", .{conf});
        exit(0);
    }

    // get the calling users UID and PASSWD information
    const uid = std.os.linux.getuid();
    const user_pass: *passwd = user.getpwuid(uid) catch |err| {
        log.err("couldn't retrieve user passwd: {s}", .{@errorName(err)});
        exit(1);
    };

    log.debug("original_uid={d} ; name={s}", .{ uid, user_pass.name.? });
    const username = try calloc.dupeZ(u8, span(user_pass.name.?));

    var target_uid: uid_t = 0;

    if (target_name) |name| {
        target_uid = user.parseuid(@ptrCast(name)) catch |err| {
            log.err("couldn't retrieve UID for '{s}': {s}", .{ name, @errorName(err) });
            exit(1);
        };
    }

    log.debug("target UID {d}", .{target_uid});

    // user_pass changes here for some reason
    const target_pass: *passwd = user.getpwuid(target_uid) catch |err| {
        log.err("couldn't retrieve target passwd for UID '{d}': {s}", .{ target_uid, @errorName(err) });
        exit(1);
    };

    const safepath = "/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin";
    var formerpath: [:0]const u8 = undefined;
    if (std.posix.getenv("PATH")) |path| {
        formerpath = path;
    } else {
        formerpath = "";
    }

    // set real and effective group ID
    std.posix.setregid(target_pass.gid, target_pass.gid) catch |err| {
        log.err("unable to set user to target GID ({d}): {s}", .{
            target_pass.gid,
            @errorName(err),
        });
        exit(1);
    };

    // initialize the supplementary group access list
    // add original user to target users groups access list
    user.initgroups(target_pass.name, target_pass.gid) catch |err| {
        log.err("unable to initgroups for target ({s}, {d}): {s}", .{
            target_pass.name.?,
            target_pass.gid,
            @errorName(err),
        });
        exit(1);
    };

    // set real and effective user ID
    std.posix.setreuid(target_pass.uid, target_pass.uid) catch |err| {
        log.err("unable to set user to target UID ({d}): {s}", .{
            target_pass.uid,
            @errorName(err),
        });
        exit(1);
    };

    // authorize the user
    log.debug("shadowauth={s}", .{user_pass.name.?});
    log.debug("shadowauth={s}", .{username});
    user.shadowauth("sweet", false) catch |err| {
        log.err("unable to authenticate user '{s}': {s}", .{ user_pass.name.?, @errorName(err) });
        exit(1);
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var env_map = try arena.allocator().create(std.process.EnvMap);
    env_map.* = try std.process.getEnvMap(arena.allocator());
    defer env_map.deinit();
    var enviter = env_map.iterator();

    while (enviter.next()) |value| {
        const key = value.key_ptr.*;
        if (eql(u8, "TERM", key) or eql(u8, "DISPLAY", key)) {
            continue;
        } else {
            env_map.remove(key);
        }
    }

    // set env
    // TODO: check if these are null properly
    try env_map.put("PATH", safepath);
    try env_map.put("HOME", span(target_pass.dir.?));
    try env_map.put("USER", span(target_pass.name.?));
    try env_map.put("LOGNAME", span(target_pass.name.?));
    try env_map.put("DOAS_USER", span(target_pass.name.?));
    try env_map.put("SHELL", span(target_pass.shell.?));

    // init our argument list
    var arglist = std.ArrayList([]const u8).init(calloc);
    errdefer arglist.deinit();

    if (run_shell) {
        // if args exist and are not null, they are greater than zero
        if (opts.args()) |_| {
            log.err("cannot pass command while specifying '-s' for running the shell", .{});
            exit(1);
        }

        if (std.posix.getenv("SHELL")) |value| {
            try arglist.append(value);
            log.debug("got shell from environment", .{});
        } else if (user_pass.shell) |value| {
            try arglist.append(span(value));
            log.debug("got shell from passwd entry", .{});
        } else {
            log.err("couldnt retrieve users shell for flag '-s'", .{});
            exit(1);
        }
    } else {
        var args = try opts.args_iter();
        while (args.next()) |value| {
            try arglist.append(value);
            log.debug("appended argument: {s}", .{value});
        }
    }

    const argv = try arglist.toOwnedSlice();
    if (argv.len == 0) {
        usage();
        exit(1);
    }

    const err = std.process.execve(calloc, argv, env_map);
    switch (err) {
        error.OutOfMemory => {
            @panic("Out of memory...");
        },
        else => {
            log.err("execve error: {s}", .{
                @errorName(err),
            });
            exit(1);
        },
    }
}
