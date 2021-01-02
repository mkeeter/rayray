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
// Jenkins hash function, specialized for a uint key
uint32_t hash(uint key) {
    uint h = 0;
    for (uint i=0; i < 4; ++i) {
        h += (key >> (i * 8)) & 0xFF;
        h += h << 10;
        h ^= h >> 6;
    }
    h += h << 3;
    h ^= h >> 11;
    h += h << 15;
    return h;
}

// Roughly based on
// https://stackoverflow.com/questions/4200224/random-noise-functions-for-glsl
float to_float(uint m) {
    const uint ieeeMantissa = 0x007FFFFFu; // binary32 mantissa bitmask
    const uint ieeeOne      = 0x3F800000u; // 1.0 in IEEE binary32

    m &= ieeeMantissa;                     // Keep only mantissa bits (fractional part)
    m |= ieeeOne;                          // Add fractional part to 1.0

    float  f = uintBitsToFloat( m );       // Range [1:2]
    return f - 1.0;                        // Range [0:1]
}

vec3 rand3(uint seed) {
    uint a = hash(seed);
    uint b = hash(a);
    uint c = hash(b);
    return vec3(to_float(a), to_float(b), to_float(c));
}

// Returns a coordinate uniformly distributed on a sphere
vec3 rand3_sphere(uint seed) {
    while (true) {
        vec3 v = rand3(seed)*2 - 1;
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
        vec3 r = rand3_sphere(seed*BOUNCES + i);

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
    // Add anti-aliasing by jittering within the pixel
    uint seed = hash(u.frame) ^ hash(floatBitsToUint(gl_FragCoord.x)) ^ hash(floatBitsToUint(gl_FragCoord.y));
    float dx = to_float(seed);
    seed = hash(seed);
    float dy = to_float(seed);

    vec2 xy = (gl_FragCoord.xy + vec2(dx, dy)) / vec2(u.width_px, u.height_px)*2 - 1;

    vec4 start = vec4(xy, 1, 0);
#if USE_PERSPECTIVE
    vec3 dir = normalize(vec3(xy/3, -1));
#else
    vec3 dir = vec3(0, 0, -1);
#endif

    fragColor = bounce(start, dir, seed);
}
