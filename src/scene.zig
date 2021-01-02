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
        try shapes.append(try Shape.new_sphere(alloc, .{ .x = -1, .y = 0, .z = 10 }, 10));
        try shapes.append(try Shape.new_sphere(alloc, .{ .x = 0.0, .y = 0.0, .z = -100 }, 50));

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

    pub fn encode(self: *Self) ![]c.vec4 {
        var num_data: usize = 0;
        for (self.shapes.items) |s| {
            num_data += s.data.len;
        }
        var out = try self.alloc.alloc(c.vec4, num_data + self.shapes.items.len + 1);

        // Store the list length as the first element
        var i: usize = 0;
        out[i] = .{
            .x = @intToFloat(f32, self.shapes.items.len),
            .y = 0,
            .z = 0,
            .w = 0,
        };
        i += 1;

        // Skip the first item in the array
        var j: usize = self.shapes.items.len + 1;
        for (self.shapes.items) |s| {
            out[i] = .{
                .x = @intToFloat(f32, s.kind), // kind
                .y = @intToFloat(f32, j), // data offset
                .z = 0, // unused for now
                .w = 0,
            };
            std.mem.copy(c.vec4, out[j..], s.data);

            i += 1;
            j += s.data.len;
        }
        return out;
    }
};
