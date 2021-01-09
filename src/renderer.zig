const std = @import("std");

const c = @import("c.zig");
const shaderc = @import("shaderc.zig");

const Blit = @import("blit.zig").Blit;
const Raytrace = @import("raytrace.zig").Raytrace;
const Options = @import("options.zig").Options;

pub const Renderer = struct {
    const Self = @This();

    device: c.WGPUDeviceId,
    queue: c.WGPUQueueId,

    raytrace: Raytrace,
    blit: Blit,

    uniforms: c.rayUniforms,
    uniform_buf: c.WGPUBufferId,

    start_time_ms: i64,
    frame: u64,

    pub fn init(
        alloc: *std.mem.Allocator,
        options: Options,
        device: c.WGPUDeviceId,
    ) !Self {
        ////////////////////////////////////////////////////////////////////////
        // Uniform buffers (shared by both raytracing and blitter)
        const uniform_buf = c.wgpu_device_create_buffer(
            device,
            &(c.WGPUBufferDescriptor){
                .label = "blit uniforms",
                .size = @sizeOf(c.rayUniforms),
                .usage = c.WGPUBufferUsage_UNIFORM | c.WGPUBufferUsage_COPY_DST,
                .mapped_at_creation = false,
            },
        );

        const rt = try Raytrace.init(alloc, device, options, uniform_buf);
        const blit = try Blit.init(alloc, device, rt.tex_view, uniform_buf);

        var out = Renderer{
            .device = device,
            .queue = c.wgpu_device_get_default_queue(device),

            .raytrace = rt,
            .blit = blit,

            .uniforms = .{
                .width_px = options.width,
                .height_px = options.height,
                .samples = 0,
                .samples_per_frame = options.samples_per_frame,

                .camera = rt.scene.camera,
            },
            .uniform_buf = uniform_buf,

            .start_time_ms = 0,
            .frame = 0,
        };

        return out;
    }

    fn update_uniforms(self: *Self) void {
        c.wgpu_queue_write_buffer(
            self.queue,
            self.uniform_buf,
            0,
            @ptrCast([*c]const u8, &self.uniforms),
            @sizeOf(c.rayUniforms),
        );
    }

    pub fn draw_gui(self: *Self) bool {
        const open = c.igBegin("Camera", null, 0);
        defer c.igEnd();
        if (open) {
            const ui_changed = [_]bool{
                c.igDragFloat3("pos", @ptrCast([*c]f32, &self.uniforms.camera.pos), 0.05, -10, 10, "%.1f", 0),
                c.igDragFloat3("target", @ptrCast([*c]f32, &self.uniforms.camera.target), 0.05, -10, 10, "%.1f", 0),
                c.igDragFloat3("up", @ptrCast([*c]f32, &self.uniforms.camera.up), 0.1, -1, 1, "%.1f", 0),
                c.igDragFloat("perspective", &self.uniforms.camera.perspective, 0.01, 0, 1, "%.2f", 0),
                c.igDragFloat("defocus", &self.uniforms.camera.defocus, 0.001, 0, 0.2, "%.2f", 0),
                c.igDragFloat("focal length", &self.uniforms.camera.focal_distance, 0.01, 0, 10, "%.2f", 0),
                c.igDragFloat("scale", &self.uniforms.camera.scale, 0.05, 0, 2, "%.1f", 0),
            };
            for (ui_changed) |b| {
                if (b) {
                    return true;
                }
            }
        }
        return false;
    }

    pub fn draw(
        self: *Self,
        clear: bool,
        next_texture: c.WGPUSwapChainOutput,
        cmd_encoder: c.WGPUCommandEncoderId,
    ) void {
        if (clear) {
            self.uniforms.samples = 0;
        }

        self.update_uniforms();

        // Record the start time at the first frame, to skip startup time
        if (self.uniforms.samples == 0) {
            self.start_time_ms = std.time.milliTimestamp();
        } else if (@mod(self.frame, 10) == 0) {
            // Print stats occasionally
            std.debug.print("\r", .{});
            self.print_stats();
        }

        // Cast another set of rays, one per pixel
        self.raytrace.draw(self.uniforms.samples == 0);
        self.uniforms.samples += self.uniforms.samples_per_frame;
        self.frame += 1;

        self.blit.draw(next_texture, cmd_encoder);
    }

    fn prefix(v: *f64) u8 {
        if (v.* > 1_000_000_000) {
            v.* /= 1_000_000_000;
            return 'G';
        } else if (v.* > 1_000_000) {
            v.* /= 1_000_000;
            return 'M';
        } else if (v.* > 1_000) {
            v.* /= 1_000;
            return 'K';
        } else {
            return ' ';
        }
    }

    pub fn print_stats(self: *const Self) void {
        var ray_count = @intToFloat(f64, self.uniforms.width_px) *
            @intToFloat(f64, self.uniforms.height_px) *
            @intToFloat(f64, self.uniforms.samples);

        const dt_sec = @intToFloat(f64, std.time.milliTimestamp() - self.start_time_ms) / 1000.0;

        var rays_per_sec = ray_count / dt_sec;
        var rays_per_sec_prefix = prefix(&rays_per_sec);

        var ray_count_prefix = prefix(&ray_count);

        std.debug.print(
            "Rendered {d:.2} {c}rays in {d:.2} sec ({d:.2} {c}ray/sec, {} rays/pixel at {} x {})        ",
            .{
                ray_count,
                ray_count_prefix,
                dt_sec,
                rays_per_sec,
                rays_per_sec_prefix,
                self.uniforms.samples,
                self.uniforms.width_px,
                self.uniforms.height_px,
            },
        );
    }

    pub fn deinit(self: *Self) void {
        self.blit.deinit();
        self.raytrace.deinit();
        c.wgpu_buffer_destroy(self.uniform_buf);
    }

    pub fn update_size(self: *Self, width: u32, height: u32) void {
        self.uniforms.width_px = width;
        self.uniforms.height_px = height;
        self.uniforms.samples = 0;

        self.start_time_ms = std.time.milliTimestamp();

        self.raytrace.resize(width, height);
        self.blit.bind(self.raytrace.tex_view, self.uniform_buf);
    }
};
