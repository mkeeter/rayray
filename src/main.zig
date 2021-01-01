const std = @import("std");

const c = @import("c.zig");
const Window = @import("window.zig").Window;
const Renderer = @import("renderer.zig").Renderer;

pub fn main() anyerror!void {
    var gp_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.testing.expect(!gp_alloc.deinit());
    const alloc: *std.mem.Allocator = &gp_alloc.allocator;

    if (c.glfwInit() != c.GLFW_TRUE) {
        std.debug.panic("Could not initialize glfw", .{});
    }

    var window = try Window.init(900, 600, "wgpu-pt");
    var renderer = try Renderer.init(alloc, window);
    defer alloc.destroy(renderer);
    defer renderer.deinit();

    try renderer.run();
}
