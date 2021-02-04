const std = @import("std");
const c = @import("c.zig");

pub fn save_png(
    alloc: *std.mem.Allocator,
    data: [*]const f32,
    samples: f32,
    width: usize,
    height: usize,
) !void {
    const fp = std.c.fopen("out.png", "wb") orelse
        std.debug.panic("Could not open out.png\n", .{});
    defer _ = std.c.fclose(fp);

    // Initialize write structure
    var png_ptr = c.png_create_write_struct(c.PNG_LIBPNG_VER_STRING, null, null, null);
    defer c.png_destroy_write_struct(&png_ptr, null);

    const info_ptr = c.png_create_info_struct(png_ptr) orelse
        std.debug.panic("Could not create info ptr\n", .{});

    c.png_init_io(png_ptr, @ptrCast(c.png_FILE_p, @alignCast(8, fp)));

    // Write header (8 bit colour depth)
    c.png_set_IHDR(png_ptr, info_ptr, @intCast(c_uint, width), @intCast(c_uint, height), 8, c.PNG_COLOR_TYPE_RGB, c.PNG_INTERLACE_NONE, c.PNG_COMPRESSION_TYPE_BASE, c.PNG_FILTER_TYPE_BASE);

    c.png_write_info(png_ptr, info_ptr);

    var row = try alloc.alloc(u8, width * 3);
    defer alloc.free(row);
    var y: usize = 0;
    while (y < height) : (y += 1) {
        // Copy RGB data into row
        var x: usize = 0;
        const d = (height - y - 1) * width * 4;
        while (x < width) : (x += 1) {
            row[x * 3 + 0] = @floatToInt(u8, std.math.clamp(data[d + x * 4 + 0] / samples, 0, 1) * 255);
            row[x * 3 + 1] = @floatToInt(u8, std.math.clamp(data[d + x * 4 + 1] / samples, 0, 1) * 255);
            row[x * 3 + 2] = @floatToInt(u8, std.math.clamp(data[d + x * 4 + 2] / samples, 0, 1) * 255);
        }
        c.png_write_row(png_ptr, row.ptr);
    }

    c.png_write_end(png_ptr, null);
}
