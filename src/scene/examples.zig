const std = @import("std");

const vec3 = @import("vec3.zig");

const Scene = @import("../scene.zig").Scene;
const Shape = @import("shape.zig").Shape;
const Material = @import("material.zig").Material;

pub fn new_light_scene(alloc: *std.mem.Allocator) !Scene {
    var scene = Scene.new(alloc);
    const light = try scene.new_material(Material.new_light(1, 1, 1, 1));
    try scene.shapes.append(Shape.new_sphere(
        .{ .x = 0, .y = 0, .z = 0 },
        0.2,
        light,
    ));
    return scene;
}

pub fn new_orb_scene(alloc: *std.mem.Allocator) !Scene {
    var scene = Scene.new(alloc);
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

pub fn new_simple_scene(alloc: *std.mem.Allocator) !Scene {
    var scene = Scene.new(alloc);
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

pub fn new_white_box(alloc: *std.mem.Allocator) !Scene {
    var scene = Scene.new(alloc);
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

pub fn new_hex_box(alloc: *std.mem.Allocator) !Scene {
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

pub fn new_cornell_box(alloc: *std.mem.Allocator) !Scene {
    var scene = Scene.new(alloc);
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

pub fn new_cornell_balls(alloc: *std.mem.Allocator) !Scene {
    var scene = Scene.new(alloc);
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

pub fn new_cornell_aberration(alloc: *std.mem.Allocator) !Scene {
    var scene = try new_cornell_balls(alloc);
    scene.camera.pos = .{ .x = 0, .y = -0.6, .z = 1 };
    scene.camera.target = .{ .x = 0, .y = -0.6, .z = 0 };
    scene.camera.defocus = 0;
    scene.camera.scale = 0.4;
    return scene;
}

pub fn new_rtiow(alloc: *std.mem.Allocator) !Scene {
    // Initialize the RNG
    var buf: [8]u8 = undefined;
    try std.os.getrandom(buf[0..]);
    const seed = std.mem.readIntLittle(u64, buf[0..8]);

    var r = std.rand.DefaultPrng.init(seed);

    var scene = Scene.new(alloc);
    scene.camera = .{
        .pos = .{ .x = 8, .y = 1.5, .z = 2 },
        .target = .{ .x = 0, .y = 0, .z = 0 },
        .up = .{ .x = 0, .y = 1, .z = 0 },
        .scale = 1,
        .defocus = 0.03,
        .perspective = 0.4,
        .focal_distance = 4.0,
    };

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

pub fn new_horizon(alloc: *std.mem.Allocator) !Scene {
    var scene = Scene.new(alloc);
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

pub fn new_prism(alloc: *std.mem.Allocator) !Scene {
    var scene = Scene.new(alloc);
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

pub fn new_caffeine(alloc: *std.mem.Allocator) !Scene {
    var scene = try @import("mol.zig").from_mol_file(alloc, "data/caffeine.mol");
    scene.camera.defocus = 0;
    scene.camera.pos.z = 2;
    scene.camera.perspective = 0.1;
    scene.camera.scale = 5;

    const light = try scene.new_material(Material.new_light(1, 1, 1, 5));
    try scene.shapes.append(
        Shape.new_sphere(.{ .x = 3.5, .y = 4.5, .z = 10 }, 5, light),
    );

    return scene;
}
