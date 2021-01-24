const std = @import("std");

const c = @import("c.zig");
const shaderc = @import("shaderc.zig");
const Scene = @import("scene.zig").Scene;

pub const AsyncShaderc = struct {
    const Self = @This();

    alloc: *std.mem.Allocator,

    mutex: std.Mutex,
    thread: *std.Thread,
    cancelled: bool,

    device: c.WGPUDeviceId,
    scene: Scene,
    out: ?c.WGPUShaderModuleId,

    pub fn init(scene: Scene, device: c.WGPUDeviceId) Self {
        return Self{
            .alloc = scene.alloc,

            .mutex = std.Mutex{},
            .thread = undefined, // defined in start()

            .scene = scene,
            .device = device,
            .out = null,
            .cancelled = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.thread.wait();
        self.scene.deinit();
    }

    pub fn start(self: *Self) !void {
        self.thread = try std.Thread.spawn(self, Self.run);
    }

    fn run(self: *Self) void {
        const txt = self.scene.trace_glsl() catch |err| {
            std.debug.panic("Failed to generate GLSL: {}\n", .{err});
        };
        defer self.alloc.free(txt);
        const frag_spv = shaderc.build_shader(self.alloc, "rt", txt) catch |err| {
            std.debug.panic("Failed to build shader: {}\n", .{err});
        };
        defer self.alloc.free(frag_spv);

        // The fragment shader is pre-compiled in a separate thread, because
        // it could take a while.
        const frag_shader = c.wgpu_device_create_shader_module(
            self.device,
            &(c.WGPUShaderModuleDescriptor){
                .label = "compiled frag shader",
                .bytes = frag_spv.ptr,
                .length = frag_spv.len,
                .flags = c.WGPUShaderFlags_VALIDATION,
            },
        );

        const lock = self.mutex.acquire();
        defer lock.release();
        self.out = frag_shader;
    }

    pub fn check(self: *Self) ?c.WGPUShaderModuleId {
        const lock = self.mutex.acquire();
        defer lock.release();

        // Steal the value from out
        const out = self.out;
        if (out != null) {
            self.out = null;
        }

        return out;
    }
};
