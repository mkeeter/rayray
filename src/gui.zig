const std = @import("std");

const c = @import("c.zig");

pub const Gui = struct {
    const Self = @This();

    ctx: *c.ImGuiContext,

    pub fn init(alloc: *std.mem.Allocator) Self {
        const ctx = c.igCreateContext(null);
        c.igSetCurrentContext(ctx);

        // Setup backend capabilities flags
        var io = c.igGetIO() orelse std.debug.panic("Could not get io\n", .{});
        (io.*).BackendPlatformName = "imgui_impl_glfw";

        // Keyboard mapping. ImGui will use those indices to peek into the io.KeysDown[] array.
        (io.*).KeyMap[c.ImGuiKey_Tab] = c.GLFW_KEY_TAB;
        (io.*).KeyMap[c.ImGuiKey_LeftArrow] = c.GLFW_KEY_LEFT;
        (io.*).KeyMap[c.ImGuiKey_RightArrow] = c.GLFW_KEY_RIGHT;
        (io.*).KeyMap[c.ImGuiKey_UpArrow] = c.GLFW_KEY_UP;
        (io.*).KeyMap[c.ImGuiKey_DownArrow] = c.GLFW_KEY_DOWN;
        (io.*).KeyMap[c.ImGuiKey_PageUp] = c.GLFW_KEY_PAGE_UP;
        (io.*).KeyMap[c.ImGuiKey_PageDown] = c.GLFW_KEY_PAGE_DOWN;
        (io.*).KeyMap[c.ImGuiKey_Home] = c.GLFW_KEY_HOME;
        (io.*).KeyMap[c.ImGuiKey_End] = c.GLFW_KEY_END;
        (io.*).KeyMap[c.ImGuiKey_Insert] = c.GLFW_KEY_INSERT;
        (io.*).KeyMap[c.ImGuiKey_Delete] = c.GLFW_KEY_DELETE;
        (io.*).KeyMap[c.ImGuiKey_Backspace] = c.GLFW_KEY_BACKSPACE;
        (io.*).KeyMap[c.ImGuiKey_Space] = c.GLFW_KEY_SPACE;
        (io.*).KeyMap[c.ImGuiKey_Enter] = c.GLFW_KEY_ENTER;
        (io.*).KeyMap[c.ImGuiKey_Escape] = c.GLFW_KEY_ESCAPE;
        (io.*).KeyMap[c.ImGuiKey_KeyPadEnter] = c.GLFW_KEY_KP_ENTER;
        (io.*).KeyMap[c.ImGuiKey_A] = c.GLFW_KEY_A;
        (io.*).KeyMap[c.ImGuiKey_C] = c.GLFW_KEY_C;
        (io.*).KeyMap[c.ImGuiKey_V] = c.GLFW_KEY_V;
        (io.*).KeyMap[c.ImGuiKey_X] = c.GLFW_KEY_X;
        (io.*).KeyMap[c.ImGuiKey_Y] = c.GLFW_KEY_Y;
        (io.*).KeyMap[c.ImGuiKey_Z] = c.GLFW_KEY_Z;

        return Gui{ .ctx = ctx };
    }

    pub fn deinit(self: *Self) void {
        c.igDestroyContext(self.ctx);
    }
};
