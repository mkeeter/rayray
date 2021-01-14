const std = @import("std");

const c = @import("c.zig");
const Backend = @import("gui/backend.zig").Backend;

pub const Gui = struct {
    const Self = @This();

    ctx: *c.ImGuiContext,
    backend: Backend,

    pub fn init(alloc: *std.mem.Allocator, window: *c.GLFWwindow, device: c.WGPUDeviceId) !Self {
        c.igSetAllocatorFunctions(
            c.alloc_func,
            c.free_func,
            alloc,
        );
        const ctx = c.igCreateContext(null);
        c.igSetCurrentContext(ctx);

        return Self{
            .ctx = ctx,
            .backend = try Backend.init(alloc, window, device),
        };
    }

    pub fn deinit(self: *Self) void {
        c.igDestroyContext(self.ctx);
        self.backend.deinit();
    }

    pub fn new_frame(self: *Self) void {
        c.ImGui_ImplGlfw_NewFrame();
        self.backend.new_frame();
        c.igNewFrame();
    }

    pub fn draw(
        self: *Self,
        next_texture: c.WGPUSwapChainOutput,
        cmd_encoder: c.WGPUCommandEncoderId,
    ) void {
        self.backend.draw(next_texture, cmd_encoder);
    }
};
