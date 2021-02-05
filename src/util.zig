const std = @import("std");

// Returns the file contents, loaded from the file in debug builds and
// compiled in with release builds.  alloc must be an arena allocator, to
// prevent a memory leak in debug builds; this is enforced by the signature.
pub fn file_contents(arena: *std.heap.ArenaAllocator, comptime name: []const u8) ![]const u8 {
    var alloc: *std.mem.Allocator = &arena.allocator;
    switch (std.builtin.mode) {
        .Debug => {
            const file = try std.fs.cwd().openFile(
                name,
                std.fs.File.OpenFlags{ .read = true },
            );
            const size = try file.getEndPos();
            const buf = try alloc.alloc(u8, size);
            _ = try file.readAll(buf);
            return buf;
        },
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall => {
            comptime const f = @embedFile("../" ++ name);
            return f[0..];
        },
    }
}
