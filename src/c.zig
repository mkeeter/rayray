const builtin = @import("builtin");

pub usingnamespace @cImport({
    // GLFW
    @cInclude("GLFW/glfw3.h");

    @cInclude("wgpu/wgpu.h");
    @cInclude("shaderc/shaderc.h");

    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cDefine("ImDrawIdx", "unsigned int"); // index buffer must be 4-aligned
    @cInclude("cimgui/cimgui.h");
    @cInclude("cimgui/generator/output/cimgui_impl.h");
    @cInclude("cimgui_ft/cimgui_ft.h");

    @cInclude("extern/rayray.h");

    if (builtin.os.tag == .macos) {
        @cInclude("objc/message.h");
    }
});
