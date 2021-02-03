const std = @import("std");
const builtin = @import("builtin");

pub usingnamespace @cImport({
    // System libraries
    @cInclude("GLFW/glfw3.h");
    @cInclude("png.h");

    // Vendored libraries
    @cInclude("wgpu/wgpu.h");
    @cInclude("shaderc/shaderc.h");

    // Dear ImGui
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cDefine("ImDrawIdx", "unsigned int"); // index buffer must be 4-aligned
    @cInclude("cimgui/cimgui.h");
    @cInclude("cimgui/generator/output/cimgui_impl.h");
    @cInclude("cimgui_ft/cimgui_ft.h");

    // Shared C/GLSL structs
    @cInclude("extern/rayray.h");

    if (builtin.os.tag == .macos) {
        @cInclude("objc/message.h");
    }
});

// C-compatible allocators, so we can use the Zig GPA's leak-checking
// in Dear ImGui and other C libraries.

// We'll pad every allocation with a header to recover its length
const ALLOC_OFFSET: usize = @sizeOf(std.c.max_align_t);

pub export fn alloc_func(sz: usize, user_data: ?*c_void) *c_void {
    const alloc = @ptrCast(*std.mem.Allocator, @alignCast(8, user_data));
    const full_size = sz + ALLOC_OFFSET;
    const out = alloc.allocAdvanced(
        u8,
        @alignOf(std.c.max_align_t),
        full_size,
        .exact,
    ) catch |err| {
        std.debug.panic("Could not allocate: {}\n", .{err});
    };
    std.mem.copy(u8, out[0..@sizeOf(usize)], std.mem.asBytes(&full_size));
    return &out[ALLOC_OFFSET];
}

pub export fn free_func(ptr: ?*c_void, user_data: ?*c_void) void {
    if (ptr == null) {
        return;
    }
    const alloc = @ptrCast(*std.mem.Allocator, @alignCast(8, user_data));
    var size: usize = undefined;
    const ptr_u8 = @ptrCast([*]u8, ptr) - ALLOC_OFFSET;
    std.mem.copy(u8, std.mem.asBytes(&size), ptr_u8[0..@sizeOf(usize)]);
    alloc.free(ptr_u8[0..size]);
}
