const std = @import("std");

const c = @import("c.zig");
const Options = @import("options.zig").Options;
const Renderer = @import("renderer.zig").Renderer;
const Gui = @import("gui.zig").Gui;

pub const Window = struct {
    const Self = @This();

    alloc: *std.mem.Allocator,
    window: *c.GLFWwindow,
    renderer: Renderer,
    gui: Gui,

    pub fn init(alloc: *std.mem.Allocator, opt: Options, name: [*c]const u8) !*Self {
        const window = c.glfwCreateWindow(
            @intCast(c_int, opt.width),
            @intCast(c_int, opt.height),
            name,
            null,
            null,
        );

        // Open the window!
        if (window) |w| {
            var out = try alloc.create(Self);

            // Attach the Window handle to the window so we can extract it
            _ = c.glfwSetWindowUserPointer(window, out);
            _ = c.glfwSetFramebufferSizeCallback(window, size_cb);
            _ = c.glfwSetScrollCallback(window, scroll_cb);

            const renderer = try Renderer.init(alloc, opt, w);
            out.* = .{
                .alloc = alloc,
                .window = w,
                .renderer = renderer,
                .gui = try Gui.init(alloc, renderer.device),
            };
            return out;
        } else {
            var err_str: [*c]u8 = null;
            const err = c.glfwGetError(&err_str);
            std.debug.panic("Failed to open window: {} ({})", .{ err, err_str });
        }
    }

    pub fn deinit(self: *Self) void {
        c.glfwDestroyWindow(self.window);
        self.renderer.deinit();
        self.gui.deinit();
        self.alloc.destroy(self);
    }

    pub fn should_close(self: *Self) bool {
        return c.glfwWindowShouldClose(self.window) != 0;
    }

    pub fn set_callbacks(
        self: *const Self,
        size_cb: c.GLFWframebuffersizefun,
        data: ?*c_void,
    ) void {}

    pub fn run(self: *Self) !void {
        while (!self.should_close()) {
            self.gui.new_frame();
            self.renderer.redraw();
            self.gui.draw(undefined, undefined); // TODO
            c.glfwPollEvents();
        }
        std.debug.print("\n", .{});
    }

    pub fn update_size(self: *Self, width_: c_int, height_: c_int) void {
        self.renderer.update_size(width_, height_);
    }

    pub fn on_scroll(self: *Self, dx: f64, dy: f64) void {
        self.gui.scroll(@floatCast(f32, dx), @floatCast(f32, dy));
    }
};

export fn size_cb(w: ?*c.GLFWwindow, width: c_int, height: c_int) void {
    const ptr = c.glfwGetWindowUserPointer(w) orelse std.debug.panic("Missing user pointer", .{});
    var r = @ptrCast(*Window, @alignCast(8, ptr));
    r.update_size(width, height);
}

export fn scroll_cb(w: ?*c.GLFWwindow, dx: f64, dy: f64) void {
    const ptr = c.glfwGetWindowUserPointer(w) orelse std.debug.panic("Missing user pointer", .{});
    var r = @ptrCast(*Window, @alignCast(8, ptr));
    r.on_scroll(dx, dy);
}
