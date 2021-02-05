const std = @import("std");

const c = @import("../c.zig");
const vec3 = @import("vec3.zig");
const util = @import("../util.zig");

const Scene = @import("../scene.zig").Scene;
const Shape = @import("shape.zig").Shape;
const Material = @import("material.zig").Material;

pub fn from_mol_file(alloc: *std.mem.Allocator, comptime f: []const u8) !Scene {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    const file_contents = try util.file_contents(&arena, f);
    return from_mol(alloc, file_contents);
}

const Element = enum {
    Carbon,
    Nitrogen,
    Oxygen,
    Hydrogen,

    pub fn radius(self: Element) f32 {
        return switch (self) {
            .Carbon, .Nitrogen, .Oxygen => 0.4,
            .Hydrogen => 0.2,
        };
    }

    pub fn color(self: Element) c.vec3 {
        return switch (self) {
            .Oxygen => .{ .x = 0.8, .y = 0.3, .z = 0.3 },
            .Hydrogen => .{ .x = 0.8, .y = 0.8, .z = 0.8 },
            .Nitrogen => .{ .x = 0.3, .y = 0.3, .z = 0.8 },
            .Carbon => .{ .x = 0.6, .y = 0.6, .z = 0.6 },
        };
    }
};

pub fn from_mol(alloc: *std.mem.Allocator, txt: []const u8) !Scene {
    var iter = std.mem.split(txt, "\n");

    // Ignored header
    const title = iter.next() orelse std.debug.panic("!", .{});
    const timestamp = iter.next() orelse std.debug.panic("!", .{});
    const comment = iter.next() orelse std.debug.panic("!", .{});

    const counts = iter.next() orelse std.debug.panic("!", .{});
    var count_iter = std.mem.tokenize(counts, " ");
    const n_atoms = try std.fmt.parseUnsigned(u32, count_iter.next() orelse "0", 10);
    const n_bonds = try std.fmt.parseUnsigned(u32, count_iter.next() orelse "0", 10);

    var scene = Scene.new(alloc);

    comptime const num_elems = std.meta.fields(Element).len;
    var mats: [num_elems]u32 = undefined;
    var i: u32 = 0;
    while (i < num_elems) : (i += 1) {
        const o = @intToEnum(Element, @intCast(std.meta.TagType(Element), i)).color();
        mats[i] = try scene.new_material(Material.new_diffuse(o.x, o.y, o.z));
    }

    const elements = std.ComptimeStringMap(Element, .{
        .{ "O", .Oxygen },
        .{ "N", .Nitrogen },
        .{ "C", .Carbon },
        .{ "H", .Hydrogen },
    });

    i = 0;
    while (i < n_atoms) : (i += 1) {
        const line = iter.next() orelse std.debug.panic("Missing atom\n", .{});
        var line_iter = std.mem.tokenize(line, " ");
        const x = try std.fmt.parseFloat(f32, line_iter.next() orelse "");
        const y = try std.fmt.parseFloat(f32, line_iter.next() orelse "");
        const z = try std.fmt.parseFloat(f32, line_iter.next() orelse "");
        const elem = line_iter.next() orelse "";
        const e = elements.get(elem) orelse std.debug.panic("Unknown element {}\n", .{elem});
        try scene.shapes.append(
            Shape.new_sphere(.{ .x = x, .y = y, .z = z }, e.radius(), mats[@enumToInt(e)]),
        );
    }

    return scene;
}
