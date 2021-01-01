const std = @import("std");

const c = @import("c.zig");

pub const Shape = struct {
    const Self = @This();

    kind: u32, // One of the SHAPE_* values from rayray.h
    data: []c.vec4, // Depends on kind!

    pub fn new_sphere(
        alloc: *std.mem.Allocator,
        center: c.vec3,
        radius: f32,
    ) !Self {
        var data = try alloc.alloc(c.vec4, 1);
        data[0] = .{ .x = center.x, .y = center.y, .z = center.z, .w = radius };

        return Self{
            .kind = c.SHAPE_SPHERE,
            .data = data,
        };
    }
};

pub const Scene = struct {
    const Self = @This();

    alloc: *std.mem.Allocator,
    shapes: std.ArrayList(Shape),

    pub fn new_simple_scene(alloc: *std.mem.Allocator) !Self {
        var shapes = std.ArrayList(Shape).init(alloc);
        try shapes.append(try Shape.new_sphere(alloc, .{ .x = 0, .y = 0, .z = 0 }, 1));

        return Scene{
            .alloc = alloc,
            .shapes = shapes,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.shapes.items) |s| {
            self.alloc.free(s.data);
        }
        self.shapes.deinit();
    }
};
