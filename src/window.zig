const builtin = @import("builtin");
const std = @import("std");

const c = @import("c.zig");
const Options = @import("options.zig").Options;
const Renderer = @import("renderer.zig").Renderer;
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

    pub fn init(alloc: *std.mem.Allocator, opt: Options, name: [*c]const u8) !*Self {
        const window = c.glfwCreateWindow(
            @intCast(c_int, opt.width),
            @intCast(c_int, opt.height),
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
        const width = @intCast(u32, width_);
        const height = @intCast(u32, height_);

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
        }, 2 | 4 | 8, false, adapter_cb, &adapter);

        const device = c.wgpu_adapter_request_device(
            adapter,
            0,
            &(c.WGPUCLimits){
                .max_bind_groups = 1,
            },
            true,
            null,
        );

        var out = try alloc.create(Self);

        // Attach the Window handle to the window so we can extract it
        _ = c.glfwSetWindowUserPointer(window, out);
        _ = c.glfwSetFramebufferSizeCallback(window, size_cb);

        out.* = .{
            .alloc = alloc,
            .window = window,
            .device = device,
            .queue = c.wgpu_device_get_default_queue(device),
            .surface = surface,
            .swap_chain = undefined,
            .renderer = try Renderer.init(alloc, opt, width, height, device),
            .gui = try Gui.init(alloc, window, device),
        };
        out.resize_swap_chain(width, height);
        return out;
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

    fn draw(self: *Self) void {
        const next_texture = c.wgpu_swap_chain_get_next_texture(self.swap_chain);
        if (next_texture.view_id == 0) {
            std.debug.panic("Cannot acquire next swap chain texture", .{});
        }

        const cmd_encoder = c.wgpu_device_create_command_encoder(
            self.device,
            &(c.WGPUCommandEncoderDescriptor){ .label = "main encoder" },
        );

        self.gui.new_frame();

        // Do some GUI stuff here
        if (true) {
            c.igShowDemoWindow(null);
        }
        var clear = false;
        if (c.igBegin("Camera", null, 0)) {
            const ui_changed = [_]bool{
                c.igDragFloat3("pos", @ptrCast([*c]f32, &self.renderer.uniforms.camera.pos), 0.05, -10, 10, "%.1f", 0),
                c.igDragFloat3("target", @ptrCast([*c]f32, &self.renderer.uniforms.camera.target), 0.05, -10, 10, "%.1f", 0),
                c.igDragFloat3("up", @ptrCast([*c]f32, &self.renderer.uniforms.camera.up), 0.1, -1, 1, "%.1f", 0),
                c.igDragFloat("perspective", &self.renderer.uniforms.camera.perspective, 0.01, 0, 1, "%.2f", 0),
                c.igDragFloat("defocus", &self.renderer.uniforms.camera.defocus, 0.001, 0, 0.2, "%.2f", 0),
                c.igDragFloat("focal length", &self.renderer.uniforms.camera.focal_distance, 0.01, 0, 10, "%.2f", 0),
                c.igDragFloat("scale", &self.renderer.uniforms.camera.scale, 0.05, 0, 2, "%.1f", 0),
            };
            for (ui_changed) |b| {
                clear = b or clear;
            }
        }
        c.igEnd();

        self.renderer.draw(clear, next_texture, cmd_encoder);
        self.gui.draw(next_texture, cmd_encoder);

        const cmd_buf = c.wgpu_command_encoder_finish(cmd_encoder, null);
        c.wgpu_queue_submit(self.queue, &cmd_buf, 1);

        c.wgpu_swap_chain_present(self.swap_chain);
    }

    pub fn run(self: *Self) void {
        while (!self.should_close()) {
            self.draw();
            c.glfwPollEvents();
        }
        std.debug.print("\n", .{});
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
                .usage = c.WGPUTextureUsage_OUTPUT_ATTACHMENT,
                .format = c.WGPUTextureFormat._Bgra8Unorm,
                .width = width,
                .height = height,
                .present_mode = c.WGPUPresentMode._Fifo,
            },
        );
    }
};

export fn size_cb(w: ?*c.GLFWwindow, width: c_int, height: c_int) void {
    const ptr = c.glfwGetWindowUserPointer(w) orelse std.debug.panic("Missing user pointer", .{});
    var r = @ptrCast(*Window, @alignCast(8, ptr));
    r.update_size(width, height);
}

export fn adapter_cb(received: c.WGPUAdapterId, data: ?*c_void) void {
    @ptrCast(*c.WGPUAdapterId, @alignCast(8, data)).* = received;
}
