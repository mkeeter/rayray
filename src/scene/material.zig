const std = @import("std");

const c = @import("../c.zig");

pub const Color = struct {
    const Self = @This();

    r: f32,
    g: f32,
    b: f32,

    fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        try buf.append(.{ .x = self.r, .y = self.g, .z = self.b, .w = 0 });
    }
};

pub const Diffuse = struct {
    const Self = @This();

    color: Color,
    fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        return self.color.encode(buf);
    }
};

pub const Light = struct {
    const Self = @This();

    color: Color,
    fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        return self.color.encode(buf);
    }
};

pub const Metal = struct {
    const Self = @This();

    color: Color,
    fuzz: f32,
    fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        try buf.append(.{
            .x = self.color.r,
            .y = self.color.g,
            .z = self.color.b,
            .w = self.fuzz,
        });
    }
};

pub const Glass = struct {
    const Self = @This();

    color: Color,
    eta: f32,
    fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        try buf.append(.{
            .x = self.color.r,
            .y = self.color.g,
            .z = self.color.b,
            .w = self.eta,
        });
    }
};

pub const Material = union(enum) {
    const Self = @This();

    Diffuse: Diffuse,
    Light: Light,
    Metal: Metal,
    Glass: Glass,

    pub fn tag(self: Self) u32 {
        return switch (self) {
            .Diffuse => c.MAT_DIFFUSE,
            .Light => c.MAT_LIGHT,
            .Metal => c.MAT_METAL,
            .Glass => c.MAT_GLASS,
        };
    }

    pub fn new_diffuse(r: f32, g: f32, b: f32) Self {
        return .{
            .Diffuse = Diffuse{ .color = .{ .r = r, .g = g, .b = b } },
        };
    }

    pub fn new_light(r: f32, g: f32, b: f32) Self {
        return .{
            .Light = Light{ .color = .{ .r = r, .g = g, .b = b } },
        };
    }

    pub fn new_metal(r: f32, g: f32, b: f32, fuzz: f32) Self {
        return .{
            .Metal = Metal{ .color = .{ .r = r, .g = g, .b = b }, .fuzz = fuzz },
        };
    }

    pub fn new_glass(r: f32, g: f32, b: f32, eta: f32) Self {
        return .{
            .Glass = Glass{ .color = .{ .r = r, .g = g, .b = b }, .eta = eta },
        };
    }

    pub fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        // We don't encode the tag here, because we can put it into the Shape
        // header to save space.
        return switch (self) {
            .Diffuse => |m| m.encode(buf),
            .Light => |m| m.encode(buf),
            .Metal => |m| m.encode(buf),
            .Glass => |m| m.encode(buf),
        };
    }
};
