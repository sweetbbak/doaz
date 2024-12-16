const std = @import("std");
const testing = @import("testing.zig");

const Allocator = std.mem.Allocator;

pub const LineIterator = LineIteratorSize(4096);

// Made into a generic so that we can efficiently test files larger than buffer
pub fn LineIteratorSize(comptime size: usize) type {
    return struct {
        out: []u8,
        delimiter: u8,
        file: std.fs.File,
        buffered: std.io.BufferedReader(size, std.fs.File.Reader),

        const Self = @This();

        pub const Opts = struct {
            open_flags: std.fs.File.OpenFlags = .{},
            delimiter: u8 = '\n',
        };

        pub fn deinit(self: Self) void {
            self.file.close();
        }

        pub fn next(self: *Self) !?[]u8 {
            const delimiter = self.delimiter;

            var out = self.out;
            var written: usize = 0;

            var buffered = &self.buffered;
            while (true) {
                const start = buffered.start;
                if (std.mem.indexOfScalar(u8, buffered.buf[start..buffered.end], delimiter)) |pos| {
                    const written_end = written + pos;
                    if (written_end > out.len) {
                        return error.StreamTooLong;
                    }

                    const delimiter_pos = start + pos;
                    if (written == 0) {
                        // Optimization. We haven't written anything into `out` and we have
                        // a line. We can return this directly from our buffer, no need to
                        // copy it into `out`.
                        buffered.start = delimiter_pos + 1;
                        return buffered.buf[start..delimiter_pos];
                    } else {
                        @memcpy(out[written..written_end], buffered.buf[start..delimiter_pos]);
                        buffered.start = delimiter_pos + 1;
                        return out[0..written_end];
                    }
                } else {
                    // We didn't find the delimiter. That means we need to write the rest
                    // of our buffered content to out, refill our buffer, and try again.
                    const written_end = (written + buffered.end - start);
                    if (written_end > out.len) {
                        return error.StreamTooLong;
                    }
                    @memcpy(out[written..written_end], buffered.buf[start..buffered.end]);
                    written = written_end;

                    // fill our buffer
                    const n = try buffered.unbuffered_reader.read(buffered.buf[0..]);
                    if (n == 0) {
                        return null;
                    }
                    buffered.start = 0;
                    buffered.end = n;
                }
            }
        }
    };
}

pub fn readLines(file_path: []const u8, out: []u8, opts: LineIterator.Opts) !LineIterator {
    return readLinesSize(4096, file_path, out, opts);
}

pub fn readLinesSize(comptime size: usize, file_path: []const u8, out: []u8, opts: LineIterator.Opts) !LineIteratorSize(size) {
    const file = blk: {
        if (std.fs.path.isAbsolute(file_path)) {
            break :blk try std.fs.openFileAbsolute(file_path, opts.open_flags);
        } else {
            break :blk try std.fs.cwd().openFile(file_path, opts.open_flags);
        }
    };

    const buffered = std.io.bufferedReaderSize(size, file.reader());
    return .{
        .out = out,
        .file = file,
        .buffered = buffered,
        .delimiter = opts.delimiter,
    };
}

// pub fn readJson(comptime T: type, allocator: Allocator, file_path: []const u8, opts: std.json.ParseOptions) !zul.Managed(T) {
//     const file = blk: {
//         if (std.fs.path.isAbsolute(file_path)) {
//             break :blk try std.fs.openFileAbsolute(file_path, .{});
//         } else {
//             break :blk try std.fs.cwd().openFile(file_path, .{});
//         }
//     };
//     defer file.close();
//
//     var buffered = std.io.bufferedReader(file.reader());
//     var reader = std.json.reader(allocator, buffered.reader());
//     defer reader.deinit();
//
//     var o = opts;
//     o.allocate = .alloc_always;
//     const parsed = try std.json.parseFromTokenSource(T, allocator, &reader, o);
//     return zul.Managed(T).fromJson(parsed);
// }

pub fn readDir(dir_path: []const u8) !Iterator {
    const dir = blk: {
        if (std.fs.path.isAbsolute(dir_path)) {
            break :blk try std.fs.openDirAbsolute(dir_path, .{ .iterate = true });
        } else {
            break :blk try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        }
    };

    return .{
        .dir = dir,
        .it = dir.iterate(),
    };
}

pub const Iterator = struct {
    dir: Dir,
    it: Dir.Iterator,
    arena: ?*std.heap.ArenaAllocator = null,

    const Dir = std.fs.Dir;
    const Entry = Dir.Entry;

    pub const Sort = enum {
        none,
        alphabetic,
        dir_first,
        dir_last,
    };

    pub fn deinit(self: *Iterator) void {
        self.dir.close();
        if (self.arena) |arena| {
            const allocator = arena.child_allocator;
            arena.deinit();
            allocator.destroy(arena);
        }
    }

    pub fn reset(self: *Iterator) void {
        self.it.reset();
    }

    pub fn next(self: *Iterator) !?std.fs.Dir.Entry {
        return self.it.next();
    }

    pub fn all(self: *Iterator, allocator: Allocator, sort: Sort) ![]std.fs.Dir.Entry {
        var arena = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena);

        arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        const aa = arena.allocator();

        var arr = std.ArrayList(Entry).init(aa);

        var it = self.it;
        while (try it.next()) |entry| {
            try arr.append(.{
                .kind = entry.kind,
                .name = try aa.dupe(u8, entry.name),
            });
        }

        self.arena = arena;
        const items = arr.items;

        switch (sort) {
            .alphabetic => std.sort.pdq(Entry, items, {}, sortEntriesAlphabetic),
            .dir_first => std.sort.pdq(Entry, items, {}, sortEntriesDirFirst),
            .dir_last => std.sort.pdq(Entry, items, {}, sortEntriesDirLast),
            .none => {},
        }
        return items;
    }

    fn sortEntriesAlphabetic(ctx: void, a: Entry, b: Entry) bool {
        _ = ctx;
        return std.ascii.lessThanIgnoreCase(a.name, b.name);
    }
    fn sortEntriesDirFirst(ctx: void, a: Entry, b: Entry) bool {
        _ = ctx;
        if (a.kind == b.kind) {
            return std.ascii.lessThanIgnoreCase(a.name, b.name);
        }
        return a.kind == .directory;
    }
    fn sortEntriesDirLast(ctx: void, a: Entry, b: Entry) bool {
        _ = ctx;
        if (a.kind == b.kind) {
            return std.ascii.lessThanIgnoreCase(a.name, b.name);
        }
        return a.kind != .directory;
    }
};
