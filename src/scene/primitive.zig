const std = @import("std");

const c = @import("../c.zig");

pub const Sphere = struct {
    const Self = @This();

    center: c.vec3,
    radius: f32,

    fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        try buf.append(.{
            .x = self.center.x,
            .y = self.center.y,
            .z = self.center.z,
            .w = self.radius,
        });
    }
};

pub const InfinitePlane = struct {
    const Self = @This();

    normal: c.vec3,
    offset: f32,

    fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        try buf.append(.{
            .x = self.normal.x,
            .y = self.normal.y,
            .z = self.normal.z,
            .w = self.offset,
        });
    }
};

pub const Primitive = union(enum) {
    const Self = @This();

    Sphere: Sphere,
    InfinitePlane: InfinitePlane,

    pub fn tag(self: Self) u32 {
        return switch (self) {
            .Sphere => c.SHAPE_SPHERE,
            .InfinitePlane => c.SHAPE_INFINITE_PLANE,
        };
    }

    pub fn new_sphere(p: c.vec3, radius: f32) Self {
        return .{
            .Sphere = Sphere{
                .center = p,
                .radius = radius,
            },
        };
    }

    pub fn new_infinite_plane(p: c.vec3, offset: f32) Self {
        return .{
            .InfinitePlane = InfinitePlane{
                .normal = p,
                .offset = offset,
            },
        };
    }

    pub fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        return switch (self) {
            .Sphere => |s| s.encode(buf),
            .InfinitePlane => |s| s.encode(buf),
        };
    }
};
