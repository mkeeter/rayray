const std = @import("std");

const c = @import("c.zig");
const shaderc = @import("shaderc.zig");
const Scene = @import("scene.zig").Scene;

pub const AsyncShaderc = struct {
    const Self = @This();

    alloc: *std.mem.Allocator,

    mutex: std.Mutex,
    thread: *std.Thread,

    scene: Scene,
    out: ?[]u32,

    pub fn init(scene: Scene) Self {
        std.debug.print("Initialized async_shaderc\n", .{});
        return Self{
            .alloc = scene.alloc,

            .mutex = std.Mutex{},
            .thread = undefined, // defined in start()

            .scene = scene,
            .out = null,
        };
    }

    pub fn deinit(self: *Self) void {
        std.debug.print("destroying async_shaderc\n", .{});
        self.thread.wait();
        self.scene.deinit();
    }

    pub fn start(self: *Self) !void {
        self.thread = try std.Thread.spawn(self, Self.run);
    }

    fn run(self: *Self) void {
        std.debug.print("shaderc thread running\n", .{});
        const txt = self.scene.trace_glsl() catch |err| {
            std.debug.panic("Failed to generate GLSL: {}\n", .{err});
        };
        defer self.alloc.free(txt);
        const out = shaderc.build_shader(self.alloc, "rt", txt) catch |err| {
            std.debug.panic("Failed to build shader: {}\n", .{err});
        };
        const lock = self.mutex.acquire();
        defer lock.release();
        self.out = out;
        std.debug.print("shaderc thread done\n", .{});
    }

    pub fn check(self: *Self) ?[]u32 {
        const lock = self.mutex.acquire();
        defer lock.release();

        // Steal the value from out
        const out = self.out;
        if (out != null) {
            std.debug.print("got output in check()\n", .{});
            self.out = null;
        }

        return out;
    }
};
