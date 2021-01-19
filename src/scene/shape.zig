const std = @import("std");

const c = @import("../c.zig");
const gui = @import("../gui.zig");
const widgets = @import("../gui/widgets.zig");

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

    pub fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        try self.prim.encode(buf);
    }

    pub fn draw_gui(self: *Self, num_materials: usize) !bool {
        var changed = false;
        if (widgets.draw_enum_combo(Primitive, self.prim)) |s| {
            changed = true;
            switch (s) {
                .Sphere => self.prim = .{
                    .Sphere = .{
                        .center = .{ .x = 0, .y = 0, .z = 0 },
                        .radius = 0.5,
                    },
                },
                .InfinitePlane => self.prim = .{
                    .InfinitePlane = .{
                        .normal = .{ .x = 0, .y = 0, .z = 1 },
                        .offset = 0,
                    },
                },
            }
        }
        var mat: c_int = @intCast(c_int, self.mat);
        c.igPushItemWidth(c.igGetWindowWidth() * 0.6);
        if (c.igDragInt("mat", &mat, 0.1, 0, @intCast(c_int, num_materials - 1), "%i", 0)) {
            self.mat = @intCast(u32, mat);
            changed = true;
        }
        changed = self.prim.draw_gui() or changed;
        c.igPopItemWidth();
        return changed;
    }

    pub fn norm_glsl(self: *const Self, alloc: *std.mem.Allocator) ![]u8 {
        return self.prim.norm_glsl(alloc);
    }
};
