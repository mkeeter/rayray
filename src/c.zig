const builtin = @import("builtin");

pub usingnamespace @cImport({
    // GLFW
    @cInclude("GLFW/glfw3.h");

    @cInclude("wgpu/wgpu.h");
    @cInclude("shaderc/shaderc.h");

    @cInclude("extern/rayray.h");

    if (builtin.os.tag == .macos) {
        @cInclude("objc/message.h");
    }
});
