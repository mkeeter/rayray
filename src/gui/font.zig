const std = @import("std");
const c = @import("../c.zig");

pub const Font = struct {
    width: u32,
    height: u32,
    pixels: [*]u8,
    bytes_per_pixel: u32,

    pub fn from_io(io: [*c]c.ImGuiIO) Font {
        var font_pixels_: ?*u8 = undefined;
        var font_width_: c_int = undefined;
        var font_height_: c_int = undefined;
        var font_bytes_per_pixel_: c_int = undefined;
        c.ImFontAtlas_GetTexDataAsRGBA32(
            io.*.Fonts,
            &font_pixels_,
            &font_width_,
            &font_height_,
            &font_bytes_per_pixel_,
        );
        return Font{
            .width = @intCast(u32, font_width_),
            .height = @intCast(u32, font_height_),
            .pixels = @ptrCast([*]u8, font_pixels_ orelse {
                std.debug.panic("Could not get font", .{});
            }),
            .bytes_per_pixel = @intCast(u32, font_bytes_per_pixel_),
        };
    }
};
