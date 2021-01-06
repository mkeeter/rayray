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

            out.* = .{
                .alloc = alloc,
                .window = w,
                .renderer = try Renderer.init(alloc, opt, w),
                .gui = Gui.init(alloc),
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
            self.renderer.redraw();
            c.glfwPollEvents();
        }
        std.debug.print("\n", .{});
    }

    pub fn update_size(self: *Self, width_: c_int, height_: c_int) void {
        self.renderer.update_size(width_, height_);
    }
};

export fn size_cb(w: ?*c.GLFWwindow, width: c_int, height: c_int) void {
    const ptr = c.glfwGetWindowUserPointer(w) orelse std.debug.panic("Missing user pointer", .{});
    var r = @ptrCast(*Window, @alignCast(8, ptr));
    r.update_size(width, height);
}
