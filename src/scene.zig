const std = @import("std");

const c = @import("c.zig");
const vec3 = @import("scene/vec3.zig");

const Shape = @import("scene/shape.zig").Shape;
const Material = @import("scene/material.zig").Material;

pub const Scene = struct {
    const Self = @This();

    alloc: *std.mem.Allocator,
    shapes: std.ArrayList(Shape),
    materials: std.ArrayList(Material),
    camera: c.rayCamera,

    pub fn new(alloc: *std.mem.Allocator) Self {
        return Scene{
            .alloc = alloc,

            .shapes = std.ArrayList(Shape).init(alloc),
            .materials = std.ArrayList(Material).init(alloc),
            .camera = default_camera(),
        };
    }

    pub fn add_cube(
        self: *Self,
        center: c.vec3,
        dx: c.vec3,
        dy: c.vec3,
        // dz is implied by cross(dx, dy)
        size: c.vec3,
        mat: u32,
    ) !void {
        const dz = vec3.cross(dx, dy);
        const x = vec3.dot(center, dx);
        const y = vec3.dot(center, dy);
        const z = vec3.dot(center, dz);
        try self.shapes.append(Shape.new_finite_plane(
            dx,
            x + size.x / 2,
            dy,
            .{
                .x = y - size.y / 2,
                .y = y + size.y / 2,
                .z = z - size.z / 2,
                .w = z + size.z / 2,
            },
            mat,
        ));
        try self.shapes.append(Shape.new_finite_plane(
            vec3.neg(dx),
            -(x - size.x / 2),
            dy,
            .{
                .x = y - size.y / 2,
                .y = y + size.y / 2,
                .z = -z - size.z / 2,
                .w = -z + size.z / 2,
            },
            mat,
        ));
        try self.shapes.append(Shape.new_finite_plane(
            dy,
            y + size.y / 2,
            dx,
            .{
                .x = x - size.x / 2,
                .y = x + size.x / 2,
                .z = -z - size.z / 2,
                .w = -z + size.z / 2,
            },
            mat,
        ));
        try self.shapes.append(Shape.new_finite_plane(
            vec3.neg(dy),
            -(y - size.y / 2),
            dx,
            .{
                .x = x - size.x / 2,
                .y = x + size.x / 2,
                .z = z - size.z / 2,
                .w = z + size.z / 2,
            },
            mat,
        ));
        try self.shapes.append(Shape.new_finite_plane(
            dz,
            z + size.z / 2,
            dx,
            .{
                .x = x - size.x / 2,
                .y = x + size.x / 2,
                .z = y - size.y / 2,
                .w = y + size.y / 2,
            },
            mat,
        ));
        try self.shapes.append(Shape.new_finite_plane(
            vec3.neg(dz),
            -(z - size.z / 2),
            dx,
            .{
                .x = x - size.x / 2,
                .y = x + size.x / 2,
                .z = -y - size.y / 2,
                .w = -y + size.y / 2,
            },
            mat,
        ));
    }

    pub fn clone(self: *const Self) !Self {
        var shapes = try std.ArrayList(Shape).initCapacity(
            self.alloc,
            self.shapes.items.len,
        );
        for (self.shapes.items) |s| {
            try shapes.append(s);
        }
        var materials = try std.ArrayList(Material).initCapacity(
            self.alloc,
            self.materials.items.len,
        );
        for (self.materials.items) |m| {
            try materials.append(m);
        }
        return Self{
            .alloc = self.alloc,
            .shapes = shapes,
            .materials = materials,
            .camera = self.camera,
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

    pub fn new_material(self: *Self, m: Material) !u32 {
        try self.materials.append(m);
        return @intCast(u32, self.materials.items.len - 1);
    }

    pub fn deinit(self: *Self) void {
        self.shapes.deinit();
        self.materials.deinit();
    }

    pub fn encode(self: *const Self) ![]c.vec4 {
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

    fn del_shape(self: *Self, index: usize) void {
        var i = index;
        while (i < self.shapes.items.len - 1) : (i += 1) {
            self.shapes.items[i] = self.shapes.items[i + 1];
        }
        _ = self.shapes.pop();
    }

    fn del_material(self: *Self, index: usize) void {
        var i = index;
        for (self.shapes.items) |*s| {
            if (s.mat == index) {
                s.mat = 0;
            } else if (s.mat > index) {
                s.mat -= 1;
            }
        }
        while (i < self.materials.items.len - 1) : (i += 1) {
            self.materials.items[i] = self.materials.items[i + 1];
        }
        _ = self.materials.pop();
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
                changed = true;
                self.del_shape(i);
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
            if (self.materials.items.len > 1 and
                c.igButton("Delete", .{ .x = w * 0.5, .y = 0 }))
            {
                changed = true;
                self.del_material(i);
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
            \\#version 440
            \\#pragma shader_stage(compute)
            \\#include "shaders/rt_core.comp"
            \\
            \\bool trace(inout uint seed, inout vec3 pos, inout vec3 dir, inout vec4 color)
            \\{{
            \\    float best_dist = 1e8;
            \\    uint best_hit = 0;
            \\    float dist;
        , .{});
        var i: usize = 1;
        for (self.shapes.items) |shape| {
            const dist = switch (shape.prim) {
                .Sphere => |s| std.fmt.allocPrint(
                    tmp_alloc,
                    "hit_sphere(pos, dir, vec3({}, {}, {}), {})",
                    .{ s.center.x, s.center.y, s.center.z, s.radius },
                ),
                .InfinitePlane => |s| plane: {
                    const norm = vec3.normalize(s.normal);
                    break :plane std.fmt.allocPrint(
                        tmp_alloc,
                        "hit_plane(pos, dir,  vec3({}, {}, {}), {})",
                        .{ norm.x, norm.y, norm.z, s.offset },
                    );
                },
                .FinitePlane => |s| plane: {
                    const norm = vec3.normalize(s.normal);
                    const q = vec3.normalize(s.q);
                    break :plane std.fmt.allocPrint(
                        tmp_alloc,
                        \\hit_finite_plane(pos, dir,  vec3({}, {}, {}), {},
                        \\                 vec3({}, {}, {}), vec4({}, {}, {}, {}))
                    ,
                        .{
                            norm.x,     norm.y,     norm.z,     s.offset,
                            q.x,        q.y,        q.z,        s.bounds.x,
                            s.bounds.y, s.bounds.z, s.bounds.w,
                        },
                    );
                },
                .Cylinder => |s| cyl: {
                    const dir = vec3.normalize(s.dir);
                    break :cyl std.fmt.allocPrint(tmp_alloc,
                        \\hit_cylinder(pos, dir,  vec3({}, {}, {}),
                        \\             vec3({}, {}, {}),  {})
                    , .{
                        s.pos.x,  s.pos.y, s.pos.z,
                        dir.x,    dir.y,   dir.z,
                        s.radius,
                    });
                },
                .CappedCylinder => |s| capped: {
                    const delta = vec3.sub(s.end, s.pos);
                    const dir = vec3.normalize(delta);
                    break :capped std.fmt.allocPrint(
                        tmp_alloc,
                        \\hit_capped_cylinder(pos, dir,  vec3({}, {}, {}),
                        \\                    vec3({}, {}, {}),  {}, {})
                    ,
                        .{
                            s.pos.x,  s.pos.y,            s.pos.z,
                            dir.x,    dir.y,              dir.z,
                            s.radius, vec3.length(delta),
                        },
                    );
                },
            };

            out = try std.fmt.allocPrint(
                tmp_alloc,
                \\{s}
                \\    dist = {s};
                \\    if (dist > SURFACE_EPSILON && dist < best_dist) {{
                \\        best_dist = dist;
                \\        best_hit = {};
                \\    }}
            ,
                .{ out, dist, i },
            );
            i += 1;
        }

        // Close up the function, and switch to the non-temporary allocator
        out = try std.fmt.allocPrint(tmp_alloc,
            \\{s}
            \\
            \\    // If we missed all objects, terminate immediately with blackness
            \\    if (best_hit == 0) {{
            \\        color = vec4(0);
            \\        return true;
            \\    }}
            \\    pos = pos + dir*best_dist;
            \\
            \\    const uvec4 key_arr[] = {{
            \\        uvec4(0), // Dummy
        , .{out});

        var mat_count: [c.LAST_MAT]usize = undefined;
        std.mem.set(usize, mat_count[0..], 1);

        var mat_index = try tmp_alloc.alloc(usize, self.materials.items.len);
        i = 0;
        for (self.materials.items) |mat| {
            const mat_tag: u32 = mat.tag();
            const m = mat_count[mat_tag];
            mat_count[mat_tag] += 1;
            mat_index[i] = m;
            i += 1;
        }

        // Each shape needs to know its material (unless it is LIGHT)
        // We dispatch first on shape tag (SPHERE / PLANE / etc), then on
        // sub-index (0-n_shape for each shape type)
        var shape_count: [c.LAST_SHAPE]usize = undefined;
        std.mem.set(usize, shape_count[0..], 1);

        for (self.shapes.items) |shape| {
            const shape_tag: u32 = shape.prim.tag();
            const n = shape_count[shape_tag];
            shape_count[shape_tag] += 1;

            const mat_tag: u32 = self.materials.items[shape.mat].tag();
            const m = mat_index[shape.mat];
            out = try std.fmt.allocPrint(
                tmp_alloc,
                "{s}\n        uvec4({}, {}, {}, {}),",
                .{ out, shape_tag, n, mat_tag, m },
            );
        }
        out = try std.fmt.allocPrint(tmp_alloc,
            \\{s}
            \\    }};
            \\    uvec4 key = key_arr[best_hit];
            \\
        , .{out});

        var sphere_data: []u8 = "";
        var plane_data: []u8 = "";
        var finite_plane_data: []u8 = "";
        var cylinder_data: []u8 = "";
        var capped_cylinder_data: []u8 = "";

        var diffuse_data: []u8 = "";
        var light_data: []u8 = "";
        var metal_data: []u8 = "";
        var glass_data: []u8 = "";
        var laser_data: []u8 = "";

        for (self.shapes.items) |shape| {
            switch (shape.prim) {
                .Sphere => |s| sphere_data = try std.fmt.allocPrint(tmp_alloc,
                    \\{s}
                    \\                vec3({}, {}, {}),
                , .{ sphere_data, s.center.x, s.center.y, s.center.z }),
                .InfinitePlane => |s| {
                    const norm = vec3.normalize(s.normal);
                    plane_data = try std.fmt.allocPrint(tmp_alloc,
                        \\{s}
                        \\                vec3({}, {}, {}),
                    , .{ plane_data, norm.x, norm.y, norm.z });
                },
                .FinitePlane => |s| {
                    const norm = vec3.normalize(s.normal);
                    finite_plane_data = try std.fmt.allocPrint(tmp_alloc,
                        \\{s}
                        \\                vec3({}, {}, {}),
                    , .{ finite_plane_data, norm.x, norm.y, norm.z });
                },
                .Cylinder => |s| {
                    const dir = vec3.normalize(s.dir);
                    cylinder_data = try std.fmt.allocPrint(tmp_alloc,
                        \\{s}
                        \\                vec3({}, {}, {}),
                        \\                vec3({}, {}, {}),
                    , .{
                        cylinder_data, s.pos.x, s.pos.y, s.pos.z,
                        dir.x,         dir.y,   dir.z,
                    });
                },
                .CappedCylinder => |s| {
                    const delta = vec3.sub(s.end, s.pos);
                    const dir = vec3.normalize(delta);
                    capped_cylinder_data = try std.fmt.allocPrint(tmp_alloc,
                        \\{s}
                        \\            vec4({}, {}, {}, {}),
                        \\            vec4({}, {}, {}, {}),
                    , .{
                        capped_cylinder_data, s.pos.x, s.pos.y, s.pos.z,
                        s.radius,             dir.x,   dir.y,   dir.z,
                        vec3.length(delta),
                    });
                },
            }
        }

        for (self.materials.items) |mat| {
            switch (mat) {
                .Diffuse => |s| diffuse_data = try std.fmt.allocPrint(tmp_alloc,
                    \\{s}
                    \\                vec3({}, {}, {}),
                , .{ diffuse_data, s.color.r, s.color.g, s.color.b }),
                .Light => |s| light_data = try std.fmt.allocPrint(tmp_alloc,
                    \\{s}
                    \\                vec3({}, {}, {}),
                , .{ light_data, s.color.r * s.intensity, s.color.g * s.intensity, s.color.b * s.intensity }),
                .Metal => |s| metal_data = try std.fmt.allocPrint(tmp_alloc,
                    \\{s}
                    \\                vec4({}, {}, {}, {}),
                , .{ metal_data, s.color.r, s.color.g, s.color.b, s.fuzz }),
                .Glass => |s| glass_data = try std.fmt.allocPrint(tmp_alloc,
                    \\{s}
                    \\                vec2({}, {}),
                , .{ glass_data, s.eta, s.slope }),
                .Laser => |s| laser_data = try std.fmt.allocPrint(tmp_alloc,
                    \\{s}
                    \\                vec4({}, {}, {}, {}),
                , .{ laser_data, s.color.r * s.intensity, s.color.g * s.intensity, s.color.b * s.intensity, s.focus }),
                .Metaflat => {},
            }
        }

        out = try std.fmt.allocPrint(tmp_alloc,
            \\{s}
            \\    // Calculate normal based on shape type and sub-index
            \\    vec3 norm = vec3(0);
            \\    switch (key.x) {{
            \\        case SHAPE_SPHERE: {{
            \\            // Sphere centers
            \\            const vec3 data[] = {{
            \\                vec3(0), // Dummy{s}
            \\            }};
            \\            norm = norm_sphere(pos, data[key.y]);
            \\            break;
            \\        }}
            \\        case SHAPE_INFINITE_PLANE: {{
            \\            // Plane normals
            \\            const vec3 data[] = {{
            \\                vec3(0), // Dummy{s}
            \\            }};
            \\            norm = norm_plane(data[key.y]);
            \\            break;
            \\        }}
            \\        case SHAPE_FINITE_PLANE: {{
            \\            // Plane normals
            \\            const vec3 data[] = {{
            \\                vec3(0), // Dummy{s}
            \\            }};
            \\            norm = norm_plane(data[key.y]);
            \\            break;
            \\        }}
            \\        case SHAPE_CYLINDER: {{
            \\            // Cylinder centers
            \\            const vec3 data[] = {{
            \\                vec3(0), // Dummy{s}
            \\            }};
            \\            norm = norm_cylinder(pos, data[key.y*2 - 1], data[key.y*2]);
            \\            break;
            \\        }}
            \\        case SHAPE_CAPPED_CYLINDER: {{
            \\            // Cylinder centers
            \\            const vec4 data[] = {{
            \\                vec4(0), // Dummy{s}
            \\            }};
            \\            norm = norm_capped_cylinder(
            \\                pos, data[key.y*2 - 1].xyz,
            \\                data[key.y*2].xyz, data[key.y*2].w);
            \\            break;
            \\        }}
            \\    }}
            \\
            \\    // Calculate material behavior based on mat type and sub-index
            \\    switch (key.z) {{
            \\        case MAT_DIFFUSE: {{
            \\            const vec3 data[] = {{
            \\                vec3(0), // Dummy{s}
            \\            }};
            \\            return mat_diffuse(seed, color, dir, norm, data[key.w]);
            \\        }}
            \\        case MAT_LIGHT: {{
            \\            const vec3 data[] = {{
            \\                vec3(0), // Dummy{s}
            \\            }};
            \\            return mat_light(color, data[key.w]);
            \\        }}
            \\        case MAT_METAL: {{
            \\            // R, G, B, fuzz
            \\            const vec4 data[] = {{
            \\                vec4(0), // Dummy{s}
            \\            }};
            \\            vec4 m = data[key.w];
            \\            return mat_metal(seed, color, dir, norm, m.xyz, m.w);
            \\        }}
            \\        case MAT_GLASS: {{
            \\            // R, G, B, eta
            \\            const vec2 data[] = {{
            \\                vec2(0), // Dummy{s}
            \\            }};
            \\            vec2 m = data[key.w];
            \\            return mat_glass(seed, color, dir, norm, m.x, m.y);
            \\        }}
            \\        case MAT_LASER: {{
            \\            // R, G, B, focus
            \\            const vec4 data[] = {{
            \\                vec4(0), // Dummy{s}
            \\            }};
            \\            vec4 m = data[key.w];
            \\            return mat_laser(color, dir, norm, m.xyz, m.w);
            \\        }}
            \\        case MAT_METAFLAT: {{
            \\            // No parameters
            \\            return mat_metaflat(seed, dir, norm);
            \\        }}
            \\    }}
            \\
            \\    // Reaching here is an error, so set the color to green and terminate
            \\    color = vec4(0, 1, 0, 0);
            \\    return true;
            \\}}
        , .{
            out,
            sphere_data,
            plane_data,
            finite_plane_data,
            cylinder_data,
            capped_cylinder_data,
            diffuse_data,
            light_data,
            metal_data,
            glass_data,
            laser_data,
        });

        // Dupe to the standard allocator, so it won't be freed
        return self.alloc.dupe(u8, out);
    }
};
