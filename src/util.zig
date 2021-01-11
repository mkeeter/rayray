const std = @import("std");

// Returns the file contents, loaded from the file in debug builds and
// compiled in with release builds.  alloc must be an arena allocator,
// because otherwise there will be a leak.
pub fn file_contents(alloc: *std.mem.Allocator, comptime name: []const u8) ![]const u8 {
    switch (std.builtin.mode) {
        .Debug => {
            const file = try std.fs.cwd().openFile(name, std.fs.File.OpenFlags{ .read = true });
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

fn tag_array_type(comptime T: type) type {
    return [@typeInfo(@TagType(T)).Enum.fields.len][]u8;
}

pub fn tag_array(comptime T: type) tag_array_type(T) {
    comptime const tags = @typeInfo(@TagType(T)).Enum.fields;
    comptime var total_len: usize = 0;
    inline for (tags) |t| {
        total_len += t.name.len + 1;
    }
    comptime var name_array: [total_len]u8 = undefined;
    comptime var out_array: tag_array_type(T) = undefined;
    comptime var i: usize = 0;
    comptime var j: usize = 0;
    inline for (tags) |t| {
        comptime const start = i;
        inline for (t.name) |char| {
            name_array[i] = char;
            i += 1;
        }
        name_array[i] = 0;
        i += 1;
        out_array[j] = name_array[start..i];
        j += 1;
    }
    return out_array;
}
