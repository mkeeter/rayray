const std = @import("std");

const c = @import("c.zig");

const Shape = @import("scene/shape.zig").Shape;
const Material = @import("scene/material.zig").Material;

pub const Scene = struct {
    const Self = @This();

    alloc: *std.mem.Allocator,
    shapes: std.ArrayList(Shape),
    materials: std.ArrayList(Material),
    camera: c.rayCamera,

    fn new(alloc: *std.mem.Allocator, camera: c.rayCamera) Self {
        return Scene{
            .alloc = alloc,
            .shapes = std.ArrayList(Shape).init(alloc),
            .materials = std.ArrayList(Material).init(alloc),
            .camera = camera,
        };
    }

    fn default_camera() c.rayCamera {
        return .{
            .pos = .{ .x = 0, .y = 0, .z = 1 },
            .target = .{ .x = 0, .y = 0, .z = 0 },
            .up = .{ .x = 0, .y = 1, .z = 0 },
            .scale = 1,
            .defocus = 0.02,
            .perspective = 0.4,
            .focal_distance = 0.8,
        };
    }

    fn new_material(self: *Self, m: Material) !u32 {
        try self.materials.append(m);
        return @intCast(u32, self.materials.items.len - 1);
    }

    pub fn new_light_scene(alloc: *std.mem.Allocator) !Self {
        var scene = new(alloc, default_camera());
        const light = try scene.new_material(Material.new_light(1, 1, 1, 1));
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 0, .y = 0, .z = 0 },
            0.2,
            light,
        ));
        return scene;
    }

    pub fn new_simple_scene(alloc: *std.mem.Allocator) !Self {
        var scene = new(alloc, default_camera());
        const white = try scene.new_material(Material.new_diffuse(1, 1, 1));
        const red = try scene.new_material(Material.new_diffuse(1, 0.2, 0.2));
        const light = try scene.new_material(Material.new_light(1, 1, 1, 1));

        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 0, .y = 0, .z = 0 },
            0.1,
            light,
        ));
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 0.5, .y = 0.3, .z = 0 },
            0.5,
            white,
        ));
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = -0.5, .y = 0.3, .z = 0 },
            0.3,
            red,
        ));

        return scene;
    }

    pub fn new_cornell_box(alloc: *std.mem.Allocator) !Self {
        var scene = new(alloc, default_camera());
        const white = try scene.new_material(Material.new_diffuse(1, 1, 1));
        const red = try scene.new_material(Material.new_diffuse(1, 0.1, 0.1));
        const blue = try scene.new_material(Material.new_diffuse(0.1, 0.1, 1));
        const green = try scene.new_material(Material.new_diffuse(0.1, 1, 0.1));
        const metal = try scene.new_material(Material.new_metal(1, 1, 0.5, 0.1));
        const glass = try scene.new_material(Material.new_glass(1, 1, 1, 1.5));
        const light = try scene.new_material(Material.new_light(1, 1, 1, 4));

        // Light
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 0, .y = 6.05, .z = 0 },
            5.02,
            light,
        ));
        // Back wall
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = 0, .y = 0, .z = 1 },
            -1,
            white,
        ));
        // Left wall
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = 1, .y = 0, .z = 0 },
            -1,
            red,
        ));
        // Right wall
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = -1, .y = 0, .z = 0 },
            -1,
            green,
        ));
        // Top wall
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = 0, .y = -1, .z = 0 },
            -1.05,
            white,
        ));
        // Bottom wall
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = 0, .y = 1, .z = 0 },
            -1,
            white,
        ));
        // Front wall
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = 0, .y = 0, .z = -1 },
            -1,
            white,
        ));
        // Blue sphere
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = -0.3, .y = -0.6, .z = -0.2 },
            0.4,
            blue,
        ));
        // Metal sphere
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 0.5, .y = -0.7, .z = 0.3 },
            0.3,
            metal,
        ));
        // Glass sphere
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 0.1, .y = -0.8, .z = 0.5 },
            0.2,
            glass,
        ));

        return scene;
    }

    pub fn new_rtiow(alloc: *std.mem.Allocator) !Self {
        // Initialize the RNG
        var buf: [8]u8 = undefined;
        try std.os.getrandom(buf[0..]);
        const seed = std.mem.readIntLittle(u64, buf[0..8]);

        var r = std.rand.DefaultPrng.init(seed);

        var scene = new(alloc, .{
            .pos = .{ .x = 8, .y = 1.5, .z = 2 },
            .target = .{ .x = 0, .y = 0, .z = 0 },
            .up = .{ .x = 0, .y = 1, .z = 0 },
            .scale = 1,
            .defocus = 0.03,
            .perspective = 0.4,
            .focal_distance = 4.0,
        });

        const ground_material = try scene.new_material(
            Material.new_diffuse(0.5, 0.5, 0.5),
        );
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 0, .y = -1000, .z = 0 },
            1000,
            ground_material,
        ));
        var a: i32 = -11;
        while (a < 11) : (a += 1) {
            var b: i32 = -11;
            while (b < 11) : (b += 1) {
                const x = @intToFloat(f32, a) + 0.7 * r.random.float(f32);
                const y: f32 = 0.18;
                const z = @intToFloat(f32, b) + 0.7 * r.random.float(f32);

                const da = std.math.sqrt(std.math.pow(f32, x - 4, 2) +
                    std.math.pow(f32, z, 2));
                const db = std.math.sqrt(std.math.pow(f32, x, 2) +
                    std.math.pow(f32, z, 2));
                const dc = std.math.sqrt(std.math.pow(f32, x + 4, 2) +
                    std.math.pow(f32, z, 2));

                if (da > 1.1 and db > 1.1 and dc > 1.1) {
                    const choose_mat = r.random.float(f32);
                    var mat: u32 = undefined;
                    if (choose_mat < 0.8) {
                        const red = r.random.float(f32);
                        const green = r.random.float(f32);
                        const blue = r.random.float(f32);
                        mat = try scene.new_material(
                            Material.new_diffuse(red, green, blue),
                        );
                    } else if (choose_mat < 0.95) {
                        const red = r.random.float(f32) / 2 + 1;
                        const green = r.random.float(f32) / 2 + 1;
                        const blue = r.random.float(f32) / 2 + 1;
                        const fuzz = r.random.float(f32) / 2;
                        mat = try scene.new_material(
                            Material.new_metal(red, green, blue, fuzz),
                        );
                    } else {
                        mat = try scene.new_material(
                            Material.new_glass(1, 1, 1, 1.5),
                        );
                    }
                    try scene.shapes.append(Shape.new_sphere(.{ .x = x, .y = y, .z = z }, 0.2, mat));
                }
            }
        }

        const glass = try scene.new_material(Material.new_glass(1, 1, 1, 1.5));
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 0, .y = 1, .z = 0 },
            1,
            glass,
        ));

        const diffuse = try scene.new_material(Material.new_diffuse(0.4, 0.2, 0.1));
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = -4, .y = 1, .z = 0 },
            1,
            diffuse,
        ));

        const metal = try scene.new_material(Material.new_metal(0.7, 0.6, 0.5, 0.0));
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 4, .y = 1, .z = 0 },
            1,
            metal,
        ));

        const light = try scene.new_material(Material.new_light(0.8, 0.95, 1, 1));
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 0, .y = 0, .z = 0 },
            2000,
            light,
        ));

        return scene;
    }

    pub fn new_horizon(alloc: *std.mem.Allocator) !Self {
        var scene = new(alloc);
        const blue = try scene.new_material(Material.new_diffuse(0.5, 0.5, 1));
        const red = try scene.new_material(Material.new_diffuse(1, 0.5, 0.5));
        const glass = try scene.new_material(Material.new_glass(1, 1, 1, 1.5));
        const light = try scene.new_material(Material.new_light(1, 1, 1, 1));

        // Back wall
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = 0, .y = 0, .z = 1 },
            -100,
            light,
        ));
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = 0, .y = 0, .z = -1 },
            -100,
            light,
        ));
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = 0, .y = -1, .z = 0 },
            -100,
            light,
        ));
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = 1, .y = 0, .z = 0 },
            -100,
            light,
        ));
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = -1, .y = 0, .z = 0 },
            -100,
            light,
        ));
        // Bottom wall
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = 0, .y = 1, .z = 0 },
            -1,
            blue,
        ));
        // Red sphere
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 1.25, .y = -0.5, .z = -1 },
            0.5,
            red,
        ));
        // Glass sphere
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 0.0, .y = -0.5, .z = -1 },
            0.5,
            glass,
        ));

        return scene;
    }

    pub fn deinit(self: *Self) void {
        self.shapes.deinit();
        self.materials.deinit();
    }

    pub fn encode(self: *const Self) ![]c.vec4 {
        const norm_g = try self.norm_glsl();
        defer self.alloc.free(norm_g);
        std.debug.print("norm:\n{s}\n", .{norm_g});
        const trace_g = try self.trace_glsl();
        defer self.alloc.free(trace_g);
        std.debug.print("trace:\n{s}\n", .{trace_g});

        const offset = self.shapes.items.len + 1;

        // Data is packed into an array of vec4s in a GPU buffer:
        //  num shapes | 0 | 0 | 0
        //  shape type | data offset | mat offset | mat type
        //  shape type | data offset | mat offset | mat type
        //  shape type | data offset | mat offset | mat type
        //  ...
        //  mat data (arbitrary)
        //  ...
        //  shape data
        //  ...
        //
        // Shape data is split between the "stack" (indexed in order, tightly
        // packed) and "heap" (randomly indexed, arbitrary data).
        //
        // Each shape stores an offset for the shape and material data, as well
        // as tags for shape and material type.
        //
        // (strictly speaking, the mat tag is assocated belong with the
        // material, but we had a spare slot in the vec4, so this saves memory)

        // Store the list length as the first element
        var stack = std.ArrayList(c.vec4).init(self.alloc);
        defer stack.deinit();
        try stack.append(.{
            .x = @bitCast(f32, @intCast(u32, self.shapes.items.len)),
            .y = 0,
            .z = 0,
            .w = 0,
        });

        var heap = std.ArrayList(c.vec4).init(self.alloc);
        defer heap.deinit();

        // Materials all live on the heap, with tags stored in the shapes
        var mat_indexes = std.ArrayList(u32).init(self.alloc);
        defer mat_indexes.deinit();
        for (self.materials.items) |m| {
            try mat_indexes.append(@intCast(u32, offset + heap.items.len));
            try m.encode(&heap);
        }

        // Encode all of the shapes and their respective data
        for (self.shapes.items) |s| {
            // Encode the shape's primary key
            const m = self.materials.items[s.mat];
            try stack.append(.{
                .x = @bitCast(f32, s.prim.tag()), // kind
                .y = @bitCast(f32, @intCast(u32, offset + heap.items.len)), // data offset
                .z = @bitCast(f32, mat_indexes.items[s.mat]), // mat index
                .w = @bitCast(f32, m.tag()), // mat tag
            });
            // Encode any data that the shape needs
            try s.encode(&heap);
        }

        for (heap.items) |v| {
            try stack.append(v);
        }
        return stack.toOwnedSlice();
    }

    pub fn draw_shapes_gui(self: *Self) !bool {
        var changed = false;
        var i: usize = 0;
        const num_mats = self.materials.items.len;
        const width = c.igGetWindowWidth();
        while (i < self.shapes.items.len) : (i += 1) {
            c.igPushIDPtr(@ptrCast(*c_void, &self.shapes.items[i]));
            c.igText("Shape %i:", i);
            c.igIndent(c.igGetTreeNodeToLabelSpacing());
            changed = (try self.shapes.items[i].draw_gui(num_mats)) or changed;
            c.igUnindent(c.igGetTreeNodeToLabelSpacing());

            const w = width - c.igGetCursorPosX();
            c.igIndent(w * 0.25);
            if (c.igButton("Delete", .{ .x = w * 0.5, .y = 0 })) {
                std.debug.print("Deleting shape {}\n", .{i});
            }
            c.igUnindent(w * 0.25);
            c.igSeparator();
            c.igPopID();
        }
        const w = width - c.igGetCursorPosX();
        c.igIndent(w * 0.25);
        if (c.igButton("Add shape", .{ .x = w * 0.5, .y = 0 })) {
            try self.shapes.append(Shape.new_sphere(.{ .x = 0, .y = 0, .z = 0 }, 1, 0));
            changed = true;
        }
        c.igUnindent(w * 0.25);
        return changed;
    }

    pub fn draw_materials_gui(self: *Self) !bool {
        var changed = false;
        var i: usize = 0;
        const width = c.igGetWindowWidth();
        while (i < self.materials.items.len) : (i += 1) {
            c.igPushIDPtr(@ptrCast(*c_void, &self.materials.items[i]));
            c.igText("Material %i:", i);
            c.igIndent(c.igGetTreeNodeToLabelSpacing());
            changed = (self.materials.items[i].draw_gui()) or changed;
            c.igUnindent(c.igGetTreeNodeToLabelSpacing());

            const w = width - c.igGetCursorPosX();
            c.igIndent(w * 0.25);
            if (c.igButton("Delete", .{ .x = w * 0.5, .y = 0 })) {
                std.debug.print("Deleting material {}\n", .{i});
            }
            c.igUnindent(w * 0.25);
            c.igSeparator();
            c.igPopID();
        }

        const w = c.igGetWindowWidth() - c.igGetCursorPosX();
        c.igIndent(w * 0.25);
        if (c.igButton("Add material", .{ .x = w * 0.5, .y = 0 })) {
            _ = try self.new_material(Material.new_diffuse(1, 1, 1));
            changed = true;
        }
        c.igUnindent(w * 0.25);
        return changed;
    }

    pub fn trace_glsl(self: *const Self) ![]const u8 {
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        const tmp_alloc: *std.mem.Allocator = &arena.allocator;
        defer arena.deinit();

        var out = try std.fmt.allocPrint(tmp_alloc,
            \\uint trace(inout vec3 start, vec3 dir) {{
            \\    float best_dist = 1e8;
            \\    vec3 norm = vec3(0);
            \\    uint best_hit = 0;
            \\    float dist;
        , .{});
        var i: usize = 1;
        for (self.shapes.items) |shape| {
            const line = try shape.hit_glsl(tmp_alloc);
            out = try std.fmt.allocPrint(
                tmp_alloc,
                \\{s}
                \\    dist = {s};
                \\    if (dist > SURFACE_EPSILON && dist < best_dist) {{
                \\        best_dist = dist;
                \\        best_hit = {};
                \\    }}
            ,
                .{ out, try shape.hit_glsl(tmp_alloc), i },
            );
            i += 1;
        }

        // Close up the function, and switch to the non-temporary allocator
        out = try std.fmt.allocPrint(self.alloc,
            \\{s}
            \\    if (best_hit != 0) {{
            \\        start += dir*best_dist;
            \\    }}
            \\    return best_hit;
            \\}}
        , .{out});
        return out;
    }

    pub fn mat_glsl(self: *const Self) ![]const u8 {
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        const tmp_alloc: *std.mem.Allocator = &arena.allocator;
        defer arena.deinit();

        var out = try std.fmt.allocPrint(tmp_alloc,
            \\bool mat(inout uint seed, inout vec3 color, inout vec3 dir,
            \\         uint index, vec3 pos)
            \\{{
            \\    switch (index) {{
        , .{});

        var i: usize = 1;
        for (self.shapes.items) |shape| {
            const norm = try shape.norm_glsl(tmp_alloc);
            const mat = try self.materials.items[shape.mat].mat_glsl(tmp_alloc);
            out = try std.fmt.allocPrint(
                tmp_alloc,
                \\{s}
                \\        case {}: {{
                \\            vec3 norm = {s};
                \\            return {s};
                \\        }}
            ,
                .{ out, i, norm, mat },
            );
            i += 1;
        }

        // Close up the function, and switch to the non-temporary allocator
        out = try std.fmt.allocPrint(self.alloc,
            \\{s}
            \\        default: break;
            \\    }}
            \\    return false;
            \\}}
        , .{out});
        return out;
    }
};
