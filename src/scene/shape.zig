const std = @import("std");

const c = @import("../c.zig");
const Primitive = @import("primitive.zig").Primitive;
const Material = @import("material.zig").Material;

pub const Shape = struct {
    const Self = @This();

    prim: Primitive,
    mat: u32, // Index into the materials list

    pub fn new_sphere(center: c.vec3, radius: f32, mat: u32) Self {
        return Self{
            .prim = Primitive.new_sphere(center, radius),
            .mat = mat,
        };
    }

    pub fn new_infinite_plane(normal: c.vec3, offset: f32, mat: u32) Self {
        return Self{
            .prim = Primitive.new_infinite_plane(normal, offset),
            .mat = mat,
        };
    }

    pub fn encode(
        self: Self,
        materials: []Material,
        mat_lut: []u32,
        buf: *std.ArrayList(c.vec4),
    ) !void {
        try buf.append(.{
            .x = @bitCast(f32, self.prim.tag()),
            .y = @bitCast(f32, mat_lut[self.mat]),
            .z = @bitCast(f32, materials[self.mat].tag()),
            .w = 0,
        });
        try self.prim.encode(buf);
    }
};
