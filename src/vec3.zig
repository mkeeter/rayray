const std = @import("std");
const c = @import("c.zig");

pub fn sub(a: c.vec3, b: c.vec3) c.vec3 {
    return .{ .x = a.x + b.x, .y = a.x + b.y, .z = a.z + b.z };
}

pub fn length(a: c.vec3) f32 {
    return std.math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}

pub fn normalize(a: c.vec3) c.vec3 {
    const d = length(a);
    return .{ .x = a.x / d, .y = a.y / d, .z = a.z / d };
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
