const std = @import("std");
const c = @import("c.zig");

pub fn add(a: c.vec3, b: c.vec3) c.vec3 {
    return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
}

pub fn sub(a: c.vec3, b: c.vec3) c.vec3 {
    return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
}

pub fn length(a: c.vec3) f32 {
    return std.math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}

pub fn normalize(a: c.vec3) c.vec3 {
    const d = length(a);
    return if (d == 0)
        .{ .x = 0, .y = 0, .z = 0 }
    else
        .{ .x = a.x / d, .y = a.y / d, .z = a.z / d };
}

pub fn cross(a: c.vec3, b: c.vec3) c.vec3 {
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

pub fn neg(a: c.vec3) c.vec3 {
    return .{ .x = -a.x, .y = -a.y, .z = -a.z };
}

pub fn dot(a: c.vec3, b: c.vec3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

pub fn to_vec4(a: c.vec3, w: f32) c.vec4 {
    return .{ .x = a.x, .y = a.y, .z = a.z, .w = w };
}

pub fn norm_to_vec4(a: c.vec3, w: f32) c.vec4 {
    const n = normalize(a);
    return .{ .x = n.x, .y = n.y, .z = n.z, .w = w };
}
