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

float rand(inout uint seed) {
    seed = hash(seed);

    // https://stackoverflow.com/questions/4200224/random-noise-functions-for-glsl
    uint m = seed;

    const uint ieeeMantissa = 0x007FFFFFu; // binary32 mantissa bitmask
    const uint ieeeOne      = 0x3F800000u; // 1.0 in IEEE binary32

    m &= ieeeMantissa;                     // Keep only mantissa bits (fractional part)
    m |= ieeeOne;                          // Add fractional part to 1.0

    float  f = uintBitsToFloat(m);          // Range [1:2]
    return f - 1.0;                        // Range [0:1]
}

vec3 rand3(inout uint seed) {
    return vec3(rand(seed), rand(seed), rand(seed));
}

// Returns a coordinate uniformly distributed on a sphere
vec3 rand3_sphere(inout uint seed) {
    while (true) {
        vec3 v = rand3(seed)*2 - 1;
        if (length(v) <= 1.0 && length(v) > 1e-8) {
            return normalize(v);
        }
        seed++;
    }
}

////////////////////////////////////////////////////////////////////////////////
float hit_plane(vec3 start, vec3 dir, vec3 norm, float off) {
    // dot(norm, pos) == off
    // dot(norm, start + n*dir) == off
    // dot(norm, start) + dot(norm, n*dir) == off
    // dot(norm, start) + n*dot(norm, dir) == off
    float d = (off - dot(norm, start)) / dot(norm, dir);
    return d;
}

float hit_sphere(vec3 start, vec3 dir, vec3 center, float r) {
    vec3 delta = center - start;
    float d = dot(delta, dir);
    if (d < 0) {
        return -1;
    }
    vec3 nearest = start + dir * d;
    float min_distance = length(center - nearest);
    if (min_distance < r) {
        float q = sqrt(r*r - min_distance*min_distance);
        return d - q;
    } else {
        return -1;
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
        float dist;
        switch ((uint(shape.x))) {
            case SHAPE_SPHERE: {
                vec4 d = scene_data[offset];
                dist = hit_sphere(start.xyz, dir, d.xyz, d.w);
                break;
            }
            case SHAPE_INFINITE_PLANE: {
                vec4 d = scene_data[offset];
                dist = hit_plane(start.xyz, dir, d.xyz, d.w);
                break;
            }
            default: // unimplemented shape
                continue;
        }
        if (dist > 0 && dist < best_dist) {
            best_dist = dist;
            best_hit = vec4(start.xyz + dir*dist, i);
        }
    }
    return best_hit;
}

#define BOUNCES 6
vec3 bounce(vec4 pos, vec3 dir, inout uint seed) {
    vec3 color = vec3(1);
    for (uint i=0; i < BOUNCES; ++i) {
        // Walk to the next object in the scene
        pos = trace(pos, dir);

        // If we escaped the world, then terminate
        if (pos.w == 0) {
            return vec3(0);
        }

        // Extract the shape so we can pull the material
        vec4 shape = scene_data[uint(pos.w)];

        // Look at the material and decide whether to terminate
        vec4 mat = scene_data[uint(shape.z)];
        uint mat_offset = uint(mat.y);
        uint mat_type = uint(mat.x);
        switch (mat_type) {
            // Hit a light
            case MAT_LIGHT:
                return color * scene_data[mat_offset].xyz;
            default:
                color *= scene_data[mat_offset].xyz;
                break;
        }

        vec3 n = norm(pos);
        vec3 r = rand3_sphere(seed);

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
    return vec3(0);
}

////////////////////////////////////////////////////////////////////////////////

void main() {
    // Set up our random seed based on the frame and pixel position
    uint seed = hash(hash(hash(u.frame) ^ floatBitsToUint(gl_FragCoord.x))
                                        ^ floatBitsToUint(gl_FragCoord.y));
    // Add anti-aliasing by jittering within the pixel
    float dx = rand(seed);
    float dy = rand(seed);

    vec2 xy = (gl_FragCoord.xy + vec2(dx, dy)) / vec2(u.width_px, u.height_px)*2 - 1;

    vec4 start = vec4(xy, 1, 0);
#define USE_PERSPECTIVE 1
#if USE_PERSPECTIVE
    vec3 dir = normalize(vec3(xy/3, -1));
#else
    vec3 dir = vec3(0, 0, -1);
#endif

    fragColor = vec4(bounce(start, dir, seed), 1);
}
