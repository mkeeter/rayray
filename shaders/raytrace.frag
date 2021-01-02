#version 440
#pragma shader_stage(fragment)
#include "extern/rayray.h"

layout(location=0) out vec4 fragColor;

layout(set=0, binding=0, std430) uniform Uniforms {
    raytraceUniforms u;
};
layout(set=0, binding=1) buffer Scene {
    vec4[] scene_data;
};

////////////////////////////////////////////////////////////////////////////////
// RNGs
// http://byteblacksmith.com/improvements-to-the-canonical-one-liner-glsl-rand-for-opengl-es-2-0/
float rand(vec2 co) {
    float a = 12.9898;
    float b = 78.233;
    float c = 43758.5453;
    float dt = dot(co.xy, vec2(a, b));
    float sn = mod(dt, 3.1415926);
    return fract(sin(sn) * c);
}

// Single-round randomization, which will show patterns in many cases
vec3 rand3_a(vec3 pos, uint seed) {
    float a = rand(vec2(seed, rand(pos.xy)));
    float b = rand(vec2(seed, rand(pos.xz)));
    float c = rand(vec2(seed, rand(pos.yz)));
    return vec3(a, b, c);
}

// Single-round randomization, which will show patterns in many cases
vec3 rand3_b(vec3 pos, uint seed) {
    float a = rand(vec2(rand(pos.xy), seed));
    float b = rand(vec2(rand(pos.xz), seed));
    float c = rand(vec2(rand(pos.yz), seed));
    return vec3(b, c, a);
}

// Two-round randomization, which is closer to uniform
vec3 rand3(vec3 pos, uint seed) {
    return rand3_a(rand3_b(pos, seed), seed);
}

// Returns a coordinate uniformly distributed on a sphere
vec3 rand3_sphere(vec3 pos, uint seed) {
    while (true) {
        vec3 v = rand3(pos, seed)*2 - 1;
        if (length(v) <= 1.0 && length(v) > 1e-8) {
            return normalize(v);
        }
        seed++;
    }
}

////////////////////////////////////////////////////////////////////////////////
vec4 hit_plane(vec3 start, vec3 dir, vec3 norm, float off) {
    // dot(norm, pos) == off
    // dot(norm, start + n*dir) == off
    // dot(norm, start) + dot(norm, n*dir) == off
    // dot(norm, start) + n*dot(norm, dir) == off
    float d = (off - dot(norm, start)) / dot(norm, dir);
    if (d > 0) {
        return vec4(start + d*dir, 1);
    } else {
        return vec4(0);
    }
}

vec4 hit_sphere(vec3 start, vec3 dir, vec3 center, float r) {
    vec3 delta = center - start;
    float d = dot(delta, dir);
    if (d < 0) {
        return vec4(0);
    }
    vec3 nearest = start + dir * d;
    float min_distance = length(center - nearest);
    if (min_distance < r) {
        float q = sqrt(r*r - min_distance*min_distance);
        return vec4(nearest - q*dir, 1);
    } else {
        return vec4(0);
    }
}

vec3 norm(vec4 pos) {
    vec4 shape = scene_data[uint(pos.w)];
    uint offset = uint(shape.y);
    switch (uint(shape.x)) {
        case SHAPE_SPHERE: {
            vec4 d = scene_data[offset];
            return normalize(pos.xyz - d.xyz);
        }
        case SHAPE_INFINITE_PLANE: // fallthrough
        case SHAPE_FINITE_PLANE: {
            vec4 d = scene_data[offset];
            return d.xyz;
        }
        default: // unimplemented
            return vec3(0);
    }
}

////////////////////////////////////////////////////////////////////////////////
// The lowest-level building block:
//  Raytraces to the next object in the scene,
//  returning a vec4 of [end, id]
vec4 trace(vec4 start, vec3 dir) {
    float best_dist = 1e8;
    vec4 best_hit = vec4(0);
    const uint num_shapes = uint(scene_data[0].x);

    // Avoid colliding with yourself
    uint prev_shape = uint(start.w);

    for (uint i=1; i <= num_shapes; i += 1) {
        if (i == prev_shape) {
            continue;
        }
        vec4 shape = scene_data[i];
        uint offset = uint(shape.y);
        vec4 hit = vec4(0);
        switch ((uint(shape.x))) {
            case SHAPE_SPHERE: {
                vec4 d = scene_data[offset];
                hit = hit_sphere(start.xyz, dir, d.xyz, d.w);
                break;
            }
            case SHAPE_INFINITE_PLANE: {
                vec4 d = scene_data[offset];
                hit = hit_plane(start.xyz, dir, d.xyz, d.w);
                break;
            }
            default: // unimplemented shape
                continue;
        }
        if (hit.w != 0) {
            float dist = length(hit.xyz - start.xyz);
            if (dist < best_dist) {
                best_dist = dist;
                best_hit = vec4(hit.xyz, i);
            }
        }
    }
    return best_hit;
}

#define BOUNCES 2
vec4 bounce(vec4 pos, vec3 dir, uint seed) {
    for (uint i=0; i < BOUNCES; ++i) {
        // Walk to the next object in the scene
        pos = trace(pos, dir);

        // We reached a light
        if (pos.w == 1) {
            return vec4(1);
        // We escaped the world
        } else if (pos.w == 0) {
            return vec4(0);
        }

        vec3 n = norm(pos);
        vec3 r = rand3_sphere(pos.xyz, seed*BOUNCES + i);

        // Normalize, snapping to the normal if the point on the sphere
        // is pathologically opposite it
        dir = n + r;
        float len = length(dir);
        if (len < 1e-8) {
            dir = n;
        } else {
            dir /= len;
        }
        //return vec4(dir, 1);
    }
    return vec4(0);
}

////////////////////////////////////////////////////////////////////////////////

void main() {
    float dx = 0;//rand(vec2(gl_FragCoord.x, u.frame));
    float dy = 0;//rand(vec2(gl_FragCoord.y, u.frame));

    vec2 xy = (gl_FragCoord.xy + vec2(dx, dy)) / vec2(u.width_px, u.height_px)*2 - 1;

    vec3 start = vec3(xy, 1);
#if USE_PERSPECTIVE
    vec3 dir = normalize(vec3(xy/3, -1));
#else
    vec3 dir = vec3(0, 0, -1);
#endif

    fragColor = bounce(vec4(start, 0), dir, u.frame);
}
