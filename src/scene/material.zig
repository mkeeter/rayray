const std = @import("std");

const c = @import("../c.zig");
const util = @import("../util.zig");

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
    fn draw_gui(self: *Self) bool {
        return c.igColorEdit3("color", @ptrCast([*c]f32, &self.color), 0);
    }
};

pub const Light = struct {
    const Self = @This();

    // The GUI clamps colors to 0-1, so we include a secondary multiplier
    // to adjust brightness beyond that range.
    color: Color,
    intensity: f32,

    fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        return buf.append(.{
            .x = self.color.r * self.intensity,
            .y = self.color.g * self.intensity,
            .z = self.color.b * self.intensity,
            .w = 0,
        });
    }
    fn draw_gui(self: *Self) bool {
        const a = c.igColorEdit3("color", @ptrCast([*c]f32, &self.color), 0);
        const b = c.igDragFloat("intensity", &self.intensity, 0.05, 1, 10, "%.2f", 0);
        return a or b;
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
    fn draw_gui(self: *Self) bool {
        const a = c.igColorEdit3("color", @ptrCast([*c]f32, &self.color), 0);
        const b = c.igDragFloat("fuzz", &self.fuzz, 0.01, 0, 10, "%.2f", 0);
        return a or b;
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
    fn draw_gui(self: *Self) bool {
        const a = c.igColorEdit3("color", @ptrCast([*c]f32, &self.color), 0);
        const b = c.igDragFloat("eta", &self.eta, 0.01, 1, 2, "%.2f", 0);
        return a or b;
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
            .Diffuse = .{ .color = .{ .r = r, .g = g, .b = b } },
        };
    }

    pub fn new_light(r: f32, g: f32, b: f32, intensity: f32) Self {
        return .{
            .Light = .{
                .color = .{ .r = r, .g = g, .b = b },
                .intensity = intensity,
            },
        };
    }

    pub fn new_metal(r: f32, g: f32, b: f32, fuzz: f32) Self {
        return .{
            .Metal = .{ .color = .{ .r = r, .g = g, .b = b }, .fuzz = fuzz },
        };
    }

    pub fn new_glass(r: f32, g: f32, b: f32, eta: f32) Self {
        return .{
            .Glass = .{ .color = .{ .r = r, .g = g, .b = b }, .eta = eta },
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

    fn color(self: *const Self) Color {
        return switch (self.*) {
            .Diffuse => |m| m.color,
            .Light => |m| m.color,
            .Metal => |m| m.color,
            .Glass => |m| m.color,
        };
    }

    pub fn draw_gui(self: *Self) bool {
        var changed = false;
        const tags = util.tag_array(Self);

        // Copy the slice to a null-terminated string for C API
        const my_name = tags[@enumToInt(self.*)];

        if (c.igBeginCombo("", @ptrCast([*c]const u8, my_name[0..]), 0)) {
            var i: usize = 0;
            const T = @typeInfo(@TagType(Self)).Enum.tag_type;
            while (i < tags.len) : (i += 1) {
                const is_selected = i == @enumToInt(self.*);

                const t = @ptrCast([*c]const u8, tags[i]);
                if (c.igSelectableBool(t, is_selected, 0, .{ .x = 0, .y = 0 })) {
                    changed = true;
                    switch (@intToEnum(@TagType(Self), @intCast(T, i))) {
                        .Diffuse => self.* = .{
                            .Diffuse = .{
                                .color = self.color(),
                            },
                        },
                        .Light => self.* = .{
                            .Light = .{
                                .color = self.color(),
                                .intensity = 1,
                            },
                        },
                        .Metal => self.* = .{
                            .Metal = .{
                                .color = self.color(),
                                .fuzz = 0.1,
                            },
                        },
                        .Glass => self.* = .{
                            .Glass = .{
                                .color = self.color(),
                                .eta = 0.15,
                            },
                        },
                    }
                }
                if (is_selected) {
                    c.igSetItemDefaultFocus();
                }
            }
            c.igEndCombo();
        }

        changed = switch (self.*) {
            .Diffuse => self.Diffuse.draw_gui(),
            .Light => self.Light.draw_gui(),
            .Metal => self.Metal.draw_gui(),
            .Glass => self.Glass.draw_gui(),
        } or changed;

        return changed;
    }
};
