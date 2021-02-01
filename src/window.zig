const builtin = @import("builtin");
const std = @import("std");

const c = @import("c.zig");
const Debounce = @import("debounce.zig").Debounce;
const Options = @import("options.zig").Options;
const Renderer = @import("renderer.zig").Renderer;
const Scene = @import("scene.zig").Scene;
const Gui = @import("gui.zig").Gui;

pub const Window = struct {
    const Self = @This();

    alloc: *std.mem.Allocator,

    window: *c.GLFWwindow,

    // WGPU handles
    device: c.WGPUDeviceId,
    queue: c.WGPUQueueId,
    surface: c.WGPUSurfaceId,
    swap_chain: c.WGPUSwapChainId,

    // Subsystems
    renderer: Renderer,
    gui: Gui,
    debounce: Debounce,

    focused: bool,
    show_editor: bool,
    show_gui_demo: bool,

    pub fn init(alloc: *std.mem.Allocator, options_: Options, name: [*c]const u8) !*Self {
        const window = c.glfwCreateWindow(
            @intCast(c_int, options_.width),
            @intCast(c_int, options_.height),
            name,
            null,
            null,
        ) orelse {
            var err_str: [*c]u8 = null;
            const err = c.glfwGetError(&err_str);
            std.debug.panic("Failed to open window: {} ({})", .{ err, err_str });
        };

        var width_: c_int = undefined;
        var height_: c_int = undefined;
        c.glfwGetFramebufferSize(window, &width_, &height_);
        var options = options_;
        options.width = @intCast(u32, width_);
        options.height = @intCast(u32, height_);

        // Extract the WGPU Surface from the platform-specific window
        const platform = builtin.os.tag;
        const surface = if (platform == .macos) surf: {
            // Time to do hilarious Objective-C runtime hacks, equivalent to
            //  [ns_window.contentView setWantsLayer:YES];
            //  id metal_layer = [CAMetalLayer layer];
            //  [ns_window.contentView setLayer:metal_layer];
            const objc = @import("objc.zig");
            const darwin = @import("darwin.zig");

            const cocoa_window = darwin.glfwGetCocoaWindow(window);
            const ns_window = @ptrCast(c.id, @alignCast(8, cocoa_window));

            const cv = objc.call(ns_window, "contentView");
            _ = objc.call_(cv, "setWantsLayer:", true);

            const ca_metal = objc.class("CAMetalLayer");
            const metal_layer = objc.call(ca_metal, "layer");

            _ = objc.call_(cv, "setLayer:", metal_layer);

            break :surf c.wgpu_create_surface_from_metal_layer(metal_layer);
        } else {
            std.debug.panic("Unimplemented on platform {}", .{platform});
        };

        ////////////////////////////////////////////////////////////////////////////
        // WGPU initial setup
        var adapter: c.WGPUAdapterId = 0;
        c.wgpu_request_adapter_async(&(c.WGPURequestAdapterOptions){
            .power_preference = c.WGPUPowerPreference._HighPerformance,
            .compatible_surface = surface,
        }, 2 | 4 | 8, adapter_cb, &adapter);

        const device = c.wgpu_adapter_request_device(
            adapter,
            &(c.WGPUDeviceDescriptor){
                .label = "",
                .features = 0,
                .limits = (c.WGPULimits){
                    .max_bind_groups = 1,
                },
                .trace_path = null,
            },
        );

        var out = try alloc.create(Self);

        // Attach the Window handle to the window so we can extract it
        _ = c.glfwSetWindowUserPointer(window, out);
        _ = c.glfwSetFramebufferSizeCallback(window, size_cb);
        _ = c.glfwSetWindowFocusCallback(window, focus_cb);

        const scene = try Scene.new_wave_box(alloc);
        out.* = .{
            .alloc = alloc,
            .window = window,
            .device = device,
            .queue = c.wgpu_device_get_default_queue(device),
            .surface = surface,
            .swap_chain = undefined,
            .renderer = try Renderer.init(alloc, scene, options, device),
            .gui = try Gui.init(alloc, window, device),
            .debounce = Debounce.init(),
            .show_editor = false,
            .show_gui_demo = false,
            .focused = false,
        };
        out.resize_swap_chain(options.width, options.height);

        // Trigger a compilation of an optimized shader immediately
        try out.debounce.update(0);

        return out;
    }

    pub fn deinit(self: *Self) void {
        c.glfwDestroyWindow(self.window);
        self.renderer.deinit();
        self.gui.deinit();
        self.alloc.destroy(self);
    }

    pub fn should_close(self: *const Self) bool {
        return c.glfwWindowShouldClose(self.window) != 0;
    }

    fn draw(self: *Self) !void {
        if (self.debounce.check()) {
            // Try to kick off an async build of a scene-specific shader.
            //
            // If this fails (because we've already got shaderc running),
            // then poke the debounce system to retrigger.
            var scene = try self.renderer.scene.clone();
            if (!try self.renderer.build_opt(scene)) {
                try self.debounce.update(10);
                scene.deinit();
            }
        }
        const next_texture_view = c.wgpu_swap_chain_get_current_texture_view(self.swap_chain);
        if (next_texture_view == 0) {
            std.debug.panic("Cannot acquire next swap chain texture", .{});
        }

        const cmd_encoder = c.wgpu_device_create_command_encoder(
            self.device,
            &(c.WGPUCommandEncoderDescriptor){ .label = "main encoder" },
        );

        self.gui.new_frame();

        var menu_width: f32 = 0;
        var menu_height: f32 = 0;
        if (c.igBeginMainMenuBar()) {
            if (c.igBeginMenu("Scene", true)) {
                var new_scene_fn: ?fn (alloc: *std.mem.Allocator) anyerror!Scene = null;
                if (c.igMenuItemBool("Simple", "", false, true)) {
                    new_scene_fn = Scene.new_simple_scene;
                }
                if (c.igMenuItemBool("Cornell Spheres", "", false, true)) {
                    new_scene_fn = Scene.new_cornell_balls;
                }
                if (c.igMenuItemBool("Cornell Box", "", false, true)) {
                    new_scene_fn = Scene.new_cornell_box;
                }
                if (c.igMenuItemBool("Ray Tracing in One Weekend", "", false, true)) {
                    new_scene_fn = Scene.new_rtiow;
                }
                if (c.igMenuItemBool("Prism", "", false, true)) {
                    new_scene_fn = Scene.new_prism;
                }
                if (c.igMenuItemBool("THE ORB", "", false, true)) {
                    new_scene_fn = Scene.new_orb_scene;
                }
                if (c.igMenuItemBool("Wave", "", false, true)) {
                    new_scene_fn = Scene.new_wave_box;
                }
                if (new_scene_fn) |f| {
                    const options = self.renderer.get_options();
                    self.renderer.deinit();
                    const scene = try f(self.alloc);
                    self.renderer = try Renderer.init(self.alloc, scene, options, self.device);
                    try self.debounce.update(0); // Trigger optimized shader compilation
                }
                c.igEndMenu();
            }
            if (c.igBeginMenu("View", true)) {
                _ = c.igMenuItemBoolPtr("Show editor", "", &self.show_editor, true);
                _ = c.igMenuItemBoolPtr("Show GUI demo", "", &self.show_gui_demo, true);
                c.igEndMenu();
            }
            menu_height = c.igGetWindowHeight() - 1;

            const stats = try self.renderer.stats(self.alloc);
            defer self.alloc.free(stats);
            var text_size: c.ImVec2 = undefined;
            c.igCalcTextSize(&text_size, stats.ptr, null, false, -1);

            c.igSetCursorPosX(c.igGetWindowWidth() - text_size.x - 10);
            c.igTextUnformatted(stats.ptr, null);

            c.igEndMainMenuBar();
        }

        // If the scene is changed through the editor, then poke the debounce
        // timer to build the optimized shader once things stop changing
        if (self.show_editor) {
            if (try self.renderer.draw_gui(menu_height, &menu_width)) {
                try self.debounce.update(1000);
            }
        }

        if (self.show_gui_demo) {
            c.igShowDemoWindow(&self.show_gui_demo);
        }

        const io = c.igGetIO() orelse std.debug.panic("Could not get io\n", .{});
        const pixel_density = io.*.DisplayFramebufferScale.x;
        const window_width = io.*.DisplaySize.x;
        const window_height = io.*.DisplaySize.y;
        try self.renderer.draw(
            .{
                .width = (window_width - menu_width) * pixel_density,
                .height = (window_height - menu_height) * pixel_density,
                .x = menu_width * pixel_density,
                .y = menu_height * pixel_density,
            },
            next_texture_view,
            cmd_encoder,
        );

        // Draw the GUI, which has been building render lists until now
        self.gui.draw(next_texture_view, cmd_encoder);

        const cmd_buf = c.wgpu_command_encoder_finish(cmd_encoder, null);
        c.wgpu_queue_submit(self.queue, &cmd_buf, 1);

        _ = c.wgpu_swap_chain_present(self.swap_chain);
    }

    pub fn run(self: *Self) !void {
        while (!self.should_close()) {
            try self.draw();
            if (self.focused) {
                c.glfwPollEvents();
            } else {
                c.glfwWaitEvents();
            }
        }
    }

    fn update_size(self: *Self, width_: c_int, height_: c_int) void {
        const width = @intCast(u32, width_);
        const height = @intCast(u32, height_);
        self.renderer.update_size(width, height);
        self.resize_swap_chain(width, height);
    }

    fn resize_swap_chain(self: *Self, width: u32, height: u32) void {
        self.swap_chain = c.wgpu_device_create_swap_chain(
            self.device,
            self.surface,
            &(c.WGPUSwapChainDescriptor){
                .usage = c.WGPUTextureUsage_RENDER_ATTACHMENT,
                .format = c.WGPUTextureFormat._Bgra8Unorm,
                .width = width,
                .height = height,
                .present_mode = c.WGPUPresentMode._Fifo,
            },
        );
    }

    fn update_focus(self: *Self, focused: bool) void {
        self.focused = focused;
    }
};

export fn size_cb(w: ?*c.GLFWwindow, width: c_int, height: c_int) void {
    const ptr = c.glfwGetWindowUserPointer(w) orelse std.debug.panic("Missing user pointer", .{});
    var r = @ptrCast(*Window, @alignCast(8, ptr));
    r.update_size(width, height);
}

export fn focus_cb(w: ?*c.GLFWwindow, focused: c_int) void {
    const ptr = c.glfwGetWindowUserPointer(w) orelse std.debug.panic("Missing user pointer", .{});
    var r = @ptrCast(*Window, @alignCast(8, ptr));
    r.update_focus(focused == c.GLFW_TRUE);
}

export fn adapter_cb(received: c.WGPUAdapterId, data: ?*c_void) void {
    @ptrCast(*c.WGPUAdapterId, @alignCast(8, data)).* = received;
}
