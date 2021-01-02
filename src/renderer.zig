const builtin = @import("builtin");
const std = @import("std");

const c = @import("c.zig");
const shaderc = @import("shaderc.zig");

const Window = @import("window.zig").Window;
const Blit = @import("blit.zig").Blit;
const Raytrace = @import("raytrace.zig").Raytrace;

pub const Renderer = struct {
    const Self = @This();

    window: Window,

    device: c.WGPUDeviceId,
    surface: c.WGPUSurfaceId,
    queue: c.WGPUQueueId,
    swap_chain: c.WGPUSwapChainId,

    raytrace: Raytrace,
    blit: Blit,
    rays_per_frame: usize,

    dt: [7]i64,
    dt_index: usize,

    pub fn init(alloc: *std.mem.Allocator, window: Window) !*Self {
        // Extract the WGPU Surface from the platform-specific window
        const platform = builtin.os.tag;
        const surface = if (platform == .macos) surf: {
            // Time to do hilarious Objective-C runtime hacks, equivalent to
            //  [ns_window.contentView setWantsLayer:YES];
            //  id metal_layer = [CAMetalLayer layer];
            //  [ns_window.contentView setLayer:metal_layer];
            const objc = @import("objc.zig");
            const darwin = @import("darwin.zig");

            const cocoa_window = darwin.glfwGetCocoaWindow(window.window);
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

        var width_: c_int = undefined;
        var height_: c_int = undefined;
        c.glfwGetFramebufferSize(window.window, &width_, &height_);
        const width = @intCast(u32, width_);
        const height = @intCast(u32, height_);

        const rt = try Raytrace.init(alloc, device, width, height);
        const blit = try Blit.init(alloc, device, rt.tex_view);

        const out = try alloc.create(Self);
        out.* = .{
            .window = window,
            .device = device,
            .surface = surface,
            .queue = c.wgpu_device_get_default_queue(device),
            .swap_chain = undefined,

            .raytrace = rt,
            .blit = blit,
            .rays_per_frame = 1,

            .dt = undefined,
            .dt_index = 0,
        };
        out.reset_dt();

        window.set_callbacks(
            size_cb,
            @ptrCast(?*c_void, out),
        );
        out.resize_swap_chain(width, height);

        return out;
    }

    pub fn redraw(self: *Self) void {
        const start_ms = std.time.milliTimestamp();

        // Cast another set of rays, one per pixel
        var i: usize = 0;
        while (i < self.rays_per_frame) : (i += 1) {
            self.raytrace.draw();
            self.blit.increment_sample_count();
        }

        // Begin the main render operation
        const next_texture = c.wgpu_swap_chain_get_next_texture(self.swap_chain);
        if (next_texture.view_id == 0) {
            std.debug.panic("Cannot acquire next swap chain texture", .{});
        }

        const cmd_encoder = c.wgpu_device_create_command_encoder(
            self.device,
            &(c.WGPUCommandEncoderDescriptor){ .label = "main encoder" },
        );
        self.blit.draw(next_texture, cmd_encoder);

        const cmd_buf = c.wgpu_command_encoder_finish(cmd_encoder, null);
        c.wgpu_queue_submit(self.queue, &cmd_buf, 1);
        c.wgpu_swap_chain_present(self.swap_chain);

        // Adjust rays per frame based on median-filtered framerate
        const end_ms = std.time.milliTimestamp();
        const dt = self.append_dt(end_ms - start_ms);

        if (dt < 20) {
            self.rays_per_frame += 1;
        } else if (dt > 50 and self.rays_per_frame > 1) {
            self.rays_per_frame -= 1;
        }
        std.debug.print("{} {}\n", .{ dt, self.rays_per_frame });
    }

    // Appends a new dt to the circular buffer, then returns the median
    fn append_dt(self: *Self, dt: i64) i64 {
        self.dt[self.dt_index] = dt;
        self.dt_index = (self.dt_index + 1) % self.dt.len;
        var dt_local = self.dt;
        comptime const asc = std.sort.asc(i64);
        std.sort.sort(i64, dt_local[0..], {}, asc);
        return dt_local[self.dt.len / 2];
    }

    fn reset_dt(self: *Self) void {
        var i: usize = 0;
        while (i < self.dt.len) : (i += 1) {
            self.dt[i] = 1000;
        }
        self.dt_index = 0;
    }

    pub fn run(self: *Self) !void {
        while (!self.window.should_close()) {
            self.redraw();
            c.glfwPollEvents();
        }
    }

    pub fn deinit(self: *Self) void {
        self.blit.deinit();
        self.raytrace.deinit();

        self.window.deinit();
    }

    pub fn update_size(self: *Self, width_: c_int, height_: c_int) void {
        const width = @intCast(u32, width_);
        const height = @intCast(u32, height_);

        self.resize_swap_chain(width, height);
        self.raytrace.resize(width, height);
        self.blit.bind_to_tex(self.raytrace.tex_view);
        self.reset_dt();
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

export fn adapter_cb(received: c.WGPUAdapterId, data: ?*c_void) void {
    @ptrCast(*c.WGPUAdapterId, @alignCast(8, data)).* = received;
}

export fn size_cb(w: ?*c.GLFWwindow, width: c_int, height: c_int) void {
    const ptr = c.glfwGetWindowUserPointer(w) orelse std.debug.panic("Missing user pointer", .{});
    var r = @ptrCast(*Renderer, @alignCast(8, ptr));
    r.update_size(width, height);
}
