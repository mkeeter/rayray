const std = @import("std");

const c = @import("c.zig");
const vec3 = @import("vec3.zig");

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

    fn add_cube(
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

    pub fn new_orb_scene(alloc: *std.mem.Allocator) !Self {
        var scene = new(alloc, default_camera());
        scene.camera.pos.y = 1;
        scene.camera.pos.z = 2;
        scene.camera.defocus = 0;
        const white = try scene.new_material(Material.new_diffuse(1, 1, 1));
        const light = try scene.new_material(Material.new_light(1, 1, 1, 1));

        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = 0, .y = 1, .z = 0 },
            0,
            white,
        ));
        // Centered glowing sphere
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 0, .y = 0.2, .z = 0 },
            0.5,
            light,
        ));
        // Fill light for the front face
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 2, .y = 2, .z = 3 },
            0.5,
            light,
        ));

        // Initialize the RNG
        var buf: [8]u8 = undefined;
        try std.os.getrandom(buf[0..]);
        const seed = std.mem.readIntLittle(u64, buf[0..8]);

        var r = std.rand.DefaultPrng.init(seed);

        const NUM: i32 = 4;
        const SCALE: f32 = 0.75;
        const SIZE: f32 = SCALE / @intToFloat(f32, NUM);
        var x: i32 = -NUM;

        try scene.shapes.append(Shape.new_sphere(
            .{ .x = SCALE, .y = 0.2, .z = SCALE },
            0.05,
            light,
        ));
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = -SCALE, .y = 0.2, .z = SCALE },
            0.05,
            light,
        ));
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = -SCALE, .y = 0.2, .z = -SCALE },
            0.05,
            light,
        ));
        try scene.shapes.append(Shape.new_sphere(
            .{ .x = SCALE, .y = 0.2, .z = -SCALE },
            0.05,
            light,
        ));
        while (x <= NUM) : (x += 1) {
            var z: i32 = -NUM;
            while (z <= NUM) : (z += 1) {
                const h = if (std.math.absCast(x) == NUM and std.math.absCast(z) == NUM)
                    0.1
                else
                    r.random.float(f32) * 0.1;
                try scene.add_cube(
                    .{
                        .x = @intToFloat(f32, x) * SIZE,
                        .y = h,
                        .z = @intToFloat(f32, z) * SIZE,
                    },
                    .{ .x = 1, .y = 0, .z = 0 }, // dx
                    .{ .x = 0, .y = 1, .z = 0 }, // dy
                    .{ .x = SIZE, .y = 0.2, .z = SIZE }, // size
                    white,
                );
            }
        }
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

    pub fn new_white_box(alloc: *std.mem.Allocator) !Self {
        var scene = new(alloc, default_camera());
        const white = try scene.new_material(Material.new_diffuse(1, 1, 1));
        const light = try scene.new_material(Material.new_light(1, 1, 1, 7));

        // Light
        try scene.shapes.append(Shape.new_finite_plane(
            .{ .x = 0, .y = 1, .z = 0 },
            1.04,
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = -0.25, .y = 0.25, .z = -1.0, .w = 0.25 },
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
            white,
        ));
        // Right wall
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = -1, .y = 0, .z = 0 },
            -1,
            white,
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
        return scene;
    }

    pub fn new_hex_box(alloc: *std.mem.Allocator) !Self {
        var scene = try new_white_box(alloc);
        scene.camera.defocus = 0;
        scene.camera.scale = 0.4;
        scene.camera.perspective = 1;
        scene.camera.pos = .{ .x = 0, .y = -0.4, .z = 0.7 };
        scene.camera.target = .{ .x = 0, .y = -0.6, .z = 0.3 };
        scene.camera.defocus = 0.008;
        scene.camera.focal_distance = 0.5;

        const metal = try scene.new_material(Material.new_metal(1, 0.86, 0.45, 0.2));
        const NUM: i32 = 4;
        const SCALE: f32 = 0.5;
        const SIZE: f32 = SCALE / @intToFloat(f32, NUM);
        var x = -NUM;
        while (x <= NUM) : (x += 1) {
            var z: i32 = -NUM;
            while (z <= NUM) : (z += 1) {
                const dy = std.math.sin(@intToFloat(f32, x) / @intToFloat(f32, NUM) * std.math.pi);
                var dx: f32 = 0;
                if (@rem(z, 2) == 0) {
                    dx = SIZE / 2;
                    if (x == NUM) {
                        continue;
                    }
                }
                try scene.shapes.append(Shape.new_sphere(
                    .{
                        .x = @intToFloat(f32, x) * SIZE + dx,
                        .y = -1 + SCALE / 20,
                        .z = @intToFloat(f32, z) * SIZE * 0.866,
                    },
                    SCALE / 20,
                    metal,
                ));
            }
        }
        return scene;
    }

    pub fn new_cornell_box(alloc: *std.mem.Allocator) !Self {
        var scene = new(alloc, default_camera());
        scene.camera.defocus = 0;
        const white = try scene.new_material(Material.new_diffuse(1, 1, 1));
        const red = try scene.new_material(Material.new_diffuse(1, 0.1, 0.1));
        const green = try scene.new_material(Material.new_diffuse(0.1, 1, 0.1));
        const light = try scene.new_material(Material.new_light(1, 0.8, 0.6, 6));

        // Light
        try scene.shapes.append(Shape.new_finite_plane(
            .{ .x = 0, .y = 1, .z = 0 },
            1.04,
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = -0.25, .y = 0.25, .z = -0.25, .w = 0.25 },
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

        var h: f32 = 1.3;
        try scene.add_cube(
            .{ .x = -0.35, .y = -1 + h / 2, .z = -0.3 },
            vec3.normalize(.{ .x = 0.4, .y = 0, .z = 1 }),
            vec3.normalize(.{ .x = 0, .y = 1, .z = 0 }),
            .{ .x = 0.6, .y = h, .z = 0.6 },
            white,
        );
        h = 0.6;
        try scene.add_cube(
            .{ .x = 0.35, .y = -1 + h / 2, .z = 0.3 },
            vec3.normalize(.{ .x = -0.4, .y = 0, .z = 1 }),
            vec3.normalize(.{ .x = 0, .y = 1, .z = 0 }),
            .{ .x = 0.55, .y = h, .z = 0.55 },
            white,
        );
        return scene;
    }

    pub fn new_cornell_balls(alloc: *std.mem.Allocator) !Self {
        var scene = new(alloc, default_camera());
        const white = try scene.new_material(Material.new_diffuse(1, 1, 1));
        const red = try scene.new_material(Material.new_diffuse(1, 0.1, 0.1));
        const blue = try scene.new_material(Material.new_diffuse(0.1, 0.1, 1));
        const green = try scene.new_material(Material.new_diffuse(0.1, 1, 0.1));
        const metal = try scene.new_material(Material.new_metal(1, 1, 0.5, 0.1));
        const glass = try scene.new_material(Material.new_glass(1.3, 0.0003));
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

    pub fn new_cornell_aberration(alloc: *std.mem.Allocator) !Self {
        var scene = try new_cornell_balls(alloc);
        scene.camera.pos = .{ .x = 0, .y = -0.6, .z = 1 };
        scene.camera.target = .{ .x = 0, .y = -0.6, .z = 0 };
        scene.camera.defocus = 0;
        scene.camera.scale = 0.4;
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
        const glass_mat = try scene.new_material(Material.new_glass(1.3, 0.0013));

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
                        mat = glass_mat;
                    }
                    try scene.shapes.append(Shape.new_sphere(.{ .x = x, .y = y, .z = z }, 0.2, mat));
                }
            }
        }

        try scene.shapes.append(Shape.new_sphere(
            .{ .x = 0, .y = 1, .z = 0 },
            1,
            glass_mat,
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
        const glass = try scene.new_material(Material.new_glass(1.3, 0.0013));
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

    pub fn new_prism(alloc: *std.mem.Allocator) !Self {
        var scene = new(alloc, default_camera());
        scene.camera.perspective = 0;
        scene.camera.defocus = 0;
        scene.camera.up = .{ .x = -1, .y = 0, .z = 0 };
        const light = try scene.new_material(Material.new_laser(1, 1, 1, 200, 0.999));
        const glass = try scene.new_material(Material.new_glass(1.36, 0.001));
        const white = try scene.new_material(Material.new_metaflat());

        // Back wall
        try scene.shapes.append(Shape.new_infinite_plane(
            .{ .x = 0, .y = 0, .z = 1 },
            -1,
            white,
        ));
        try scene.shapes.append(Shape.new_finite_plane(
            .{ .x = -0.259, .y = 0.966, .z = 0 },
            -1,
            .{ .x = 0, .y = 0, .z = 1 },
            .{ .x = -1, .y = 1, .z = -0.01, .w = 0.01 },
            light,
        ));
        try scene.shapes.append(Shape.new_finite_plane(
            .{ .x = -0.5, .y = -0.8660254037, .z = 0 },
            0.3,
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = -0.6, .y = 0.35, .z = -1, .w = 1 },
            glass,
        ));
        try scene.shapes.append(Shape.new_finite_plane(
            .{ .x = -0.5, .y = 0.8660254037, .z = 0 },
            0.3,
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = -0.6, .y = 0.35, .z = -1, .w = 1 },
            glass,
        ));
        // Build a triangle
        try scene.shapes.append(Shape.new_finite_plane(
            .{ .x = 0, .y = 0, .z = 1 },
            0,
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0.6, .y = 0.605, .z = -0.7, .w = 0.7 },
            light,
        ));
        try scene.shapes.append(Shape.new_finite_plane(
            .{ .x = 0, .y = 0, .z = 1 },
            0,
            .{ .x = -0.5, .y = 0.8660254037, .z = 0 },
            .{ .x = 0.3, .y = 0.305, .z = -0.87, .w = 0.525 },
            light,
        ));
        try scene.shapes.append(Shape.new_finite_plane(
            .{ .x = 0, .y = 0, .z = 1 },
            0,
            .{ .x = 0.5, .y = 0.8660254037, .z = 0 },
            .{ .x = -0.305, .y = -0.3, .z = -0.87, .w = 0.525 },
            light,
        ));

        return scene;
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
                .InfinitePlane => |s| std.fmt.allocPrint(
                    tmp_alloc,
                    "hit_plane(pos, dir,  vec3({}, {}, {}), {})",
                    .{ s.normal.x, s.normal.y, s.normal.z, s.offset },
                ),
                .FinitePlane => |s| std.fmt.allocPrint(
                    tmp_alloc,
                    \\hit_finite_plane(pos, dir,  vec3({}, {}, {}), {},
                    \\                 vec3({}, {}, {}), vec4({}, {}, {}, {}))
                ,
                    .{
                        s.normal.x, s.normal.y, s.normal.z, s.offset,
                        s.q.x,      s.q.y,      s.q.z,      s.bounds.x,
                        s.bounds.y, s.bounds.z, s.bounds.w,
                    },
                ),
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
                .InfinitePlane => |s| plane_data = try std.fmt.allocPrint(tmp_alloc,
                    \\{s}
                    \\                vec3({}, {}, {}),
                , .{ plane_data, s.normal.x, s.normal.y, s.normal.z }),
                .FinitePlane => |s| finite_plane_data = try std.fmt.allocPrint(tmp_alloc,
                    \\{s}
                    \\                vec3({}, {}, {}),
                , .{ finite_plane_data, s.normal.x, s.normal.y, s.normal.z }),
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
