const std = @import("std");

const c = @import("../c.zig");
const gui = @import("../gui.zig");

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
        return c.igColorEdit3("", @ptrCast([*c]f32, &self.color), 0);
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
        const a = c.igColorEdit3("", @ptrCast([*c]f32, &self.color), 0);
        c.igPushItemWidth(c.igGetWindowWidth() * 0.4);
        const b = c.igDragFloat("intensity", &self.intensity, 0.05, 1, 10, "%.2f", 0);
        c.igPopItemWidth();
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
        const a = c.igColorEdit3("", @ptrCast([*c]f32, &self.color), 0);
        c.igPushItemWidth(c.igGetWindowWidth() * 0.4);
        const b = c.igDragFloat("fuzz", &self.fuzz, 0.01, 0, 10, "%.2f", 0);
        c.igPopItemWidth();
        return a or b;
    }
};

pub const Glass = struct {
    const Self = @This();

    eta: f32,
    slope: f32,
    fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        try buf.append(.{
            .x = self.eta,
            .y = self.slope,
            .z = 0,
            .w = 0,
        });
    }
    fn draw_gui(self: *Self) bool {
        c.igPushItemWidth(c.igGetWindowWidth() * 0.4);
        const a = c.igDragFloat("eta", &self.eta, 0.01, 1, 2, "%.2f", 0);
        const b = c.igDragFloat("slope", &self.slope, 0.0001, 0, 0.01, "%.4f", 0);
        c.igPopItemWidth();
        return a or b;
    }
};

pub const Laser = struct {
    const Self = @This();

    // The GUI clamps colors to 0-1, so we include a secondary multiplier
    // to adjust brightness beyond that range.
    color: Color,
    intensity: f32,
    focus: f32,

    fn encode(self: Self, buf: *std.ArrayList(c.vec4)) !void {
        return buf.append(.{
            .x = self.color.r * self.intensity,
            .y = self.color.g * self.intensity,
            .z = self.color.b * self.intensity,
            .w = self.focus,
        });
    }

    fn draw_gui(self: *Self) bool {
        const a = c.igColorEdit3("", @ptrCast([*c]f32, &self.color), 0);
        c.igPushItemWidth(c.igGetWindowWidth() * 0.4);
        const b = c.igDragFloat("intensity", &self.intensity, 0.05, 1, 500, "%.2f", 0);
        const f = c.igDragFloat("focus", &self.focus, 0.01, 0, 1, "%.2f", 0);
        c.igPopItemWidth();
        return a or b or f;
    }
};

pub const Metaflat = struct {
    // Nothing in the struct
};

pub const Material = union(enum) {
    const Self = @This();

    Diffuse: Diffuse,
    Light: Light,
    Metal: Metal,
    Glass: Glass,
    Laser: Laser,
    Metaflat: Metaflat,

    pub fn tag(self: Self) u32 {
        return switch (self) {
            .Diffuse => c.MAT_DIFFUSE,
            .Light => c.MAT_LIGHT,
            .Metal => c.MAT_METAL,
            .Glass => c.MAT_GLASS,
            .Laser => c.MAT_LASER,
            .Metaflat => c.MAT_METAFLAT,
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

    pub fn new_glass(eta: f32, slope: f32) Self {
        return .{
            .Glass = .{ .eta = eta, .slope = slope },
        };
    }

    pub fn new_laser(r: f32, g: f32, b: f32, intensity: f32, focus: f32) Self {
        return .{
            .Laser = .{
                .color = .{ .r = r, .g = g, .b = b },
                .intensity = intensity,
                .focus = focus,
            },
        };
    }

    pub fn new_metaflat() Self {
        return .{
            .Metaflat = .{},
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
            .Laser => |m| m.encode(buf),
            .Metaflat => {},
        };
    }

    fn color(self: *const Self) Color {
        return switch (self.*) {
            .Diffuse => |m| m.color,
            .Light => |m| m.color,
            .Metal => |m| m.color,
            .Glass => |m| Color{ .r = 1, .g = 0.5, .b = 0.5 },
            .Laser => |m| m.color,
            .Metaflat => |m| Color{ .r = 1, .g = 0.5, .b = 0.5 },
        };
    }

    pub fn draw_gui(self: *Self) bool {
        comptime const widgets = @import("../gui/widgets.zig");
        var changed = false;
        if (widgets.draw_enum_combo(Self, self.*)) |e| {
            // Swap the material type if the combo box returns a new tag
            changed = true;
            switch (e) {
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
                        .eta = 0.15,
                        .slope = 0.013,
                    },
                },
                .Laser => self.* = .{
                    .Laser = .{
                        .color = self.color(),
                        .intensity = 1,
                        .focus = 0.5,
                    },
                },
                .Metaflat => self.* = .{
                    .Metaflat = .{},
                },
            }
        }

        changed = switch (self.*) {
            .Diffuse => |*d| d.draw_gui(),
            .Light => |*d| d.draw_gui(),
            .Metal => |*d| d.draw_gui(),
            .Glass => |*d| d.draw_gui(),
            .Laser => |*d| d.draw_gui(),
            .Metaflat => false,
        } or changed;

        return changed;
    }
};
