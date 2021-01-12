const std = @import("std");

const c = @import("../c.zig");

fn tag_array_type(comptime T: type) type {
    return [std.meta.fields(@TagType(T)).len][]u8;
}

fn tag_array(comptime T: type) tag_array_type(T) {
    comptime const tags = std.meta.fields(@TagType(T));
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

pub fn draw_enum_combo(comptime T: type, self: T) ?@TagType(T) {
    var changed = false;
    const tags = tag_array(T);

    // Copy the slice to a null-terminated string for C API
    const my_name = tags[@enumToInt(self)];

    var out: ?@TagType(T) = null;

    if (c.igBeginCombo("", @ptrCast([*c]const u8, my_name[0..]), 0)) {
        var i: usize = 0;
        const TagIntType = @typeInfo(@TagType(T)).Enum.tag_type;
        while (i < tags.len) : (i += 1) {
            const is_selected = i == @enumToInt(self);

            const t = @ptrCast([*c]const u8, tags[i]);
            if (c.igSelectableBool(t, is_selected, 0, .{ .x = 0, .y = 0 })) {
                if (i != @enumToInt(self)) {
                    out = @intToEnum(@TagType(T), @intCast(TagIntType, i));
                }
            }
            if (is_selected) {
                c.igSetItemDefaultFocus();
            }
        }
        c.igEndCombo();
    }
    return out;
}
