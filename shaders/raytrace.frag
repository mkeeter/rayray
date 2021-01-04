#version 440
#pragma shader_stage(fragment)
#include "extern/rayray.h"

layout(location=0) out vec4 fragColor;

layout(set=0, binding=0, std430) uniform Uniforms {
    rayUniforms u;
};
layout(set=0, binding=1) buffer Scene {
    vec4[] scene_data;
};

#define SURFACE_EPSILON 1e-6
#define NORMAL_EPSILON  1e-8

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
        if (length(v) <= 1.0 && length(v) > NORMAL_EPSILON) {
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
    vec3 nearest = start + dir * d;
    float min_distance = length(center - nearest);
    if (min_distance < r) {
        // Return the smallest positive intersection, plus some margin so we
        // don't get stuck against the surface.  If we're inside the
        // sphere, then this will be against a negative normal
        float q = sqrt(r*r - min_distance*min_distance);
        if (d > q + SURFACE_EPSILON) {
            return d - q;
        } else {
            return d + q;
        }
    } else {
        return -1;
    }
}

vec3 norm(vec4 pos, vec4 shape) {
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
        if (dist > SURFACE_EPSILON && dist < best_dist) {
            best_dist = dist;
            best_hit = vec4(start.xyz + dir*dist, i);
        }
    }
    return best_hit;
}


// Normalize, snapping to the normal if the vector is pathologically short
vec3 sanitize_dir(vec3 dir, vec3 norm) {
    float len = length(dir);
    if (len < NORMAL_EPSILON) {
        return norm;
    } else {
        return dir / len;
    }
}

#define BOUNCES 6
vec3 bounce(vec4 pos, vec3 dir, inout uint seed) {
    vec3 color = vec3(1);
    for (uint i=0; i < BOUNCES; ++i) {
        // Walk to the next object in the scene
        pos = trace(pos, dir);

        // If we escaped the world, then terminate immediately
        if (pos.w == 0) {
            return vec3(0);
        }

        // Extract the shape so we can pull the material
        vec4 shape = scene_data[uint(pos.w)];
        vec3 norm = norm(pos, shape);

        // Look at the material and decide whether to terminate
        vec4 mat = scene_data[uint(shape.z)];
        uint mat_type = uint(mat.x);
        uint mat_offset; // only used in some materials

        switch (mat_type) {
            // When we hit a light, return immediately
            case MAT_LIGHT:
                return color * mat.yzw;

            // Otherwise, handle the various material types
            case MAT_DIFFUSE:
                color *= mat.yzw;
                dir = sanitize_dir(norm + rand3_sphere(seed), norm);
                break;
            case MAT_METAL:
                mat_offset = uint(mat.y);
                color *= scene_data[mat_offset].xyz;
                dir -= norm * dot(norm, dir)*2;
                float fuzz = scene_data[mat_offset].w;
                if (fuzz != 0) {
                    dir += rand3_sphere(seed) * fuzz;
                    if (fuzz >= 0.99) {
                        dir = sanitize_dir(dir, norm);
                    } else {
                        dir = normalize(dir);
                    }
                }
                break;
            case MAT_GLASS:
                // This doesn't support nested materials with different etas!
                mat_offset = uint(mat.y);
                float eta = scene_data[mat_offset].w;
                // If we're entering the shape, then decide whether to reflect
                // or refract based on the incoming angle
                if (dot(dir, norm) < 0) {
                    eta = 1/eta;

                    // Use Schlick's approximation for reflectance.
                    float cosine = min(dot(-dir, norm), 1.0);
                    float r0 = (1 - eta) / (1 + eta);
                    r0 = r0*r0;
                    float reflectance = r0 + (1 - r0) * pow((1 - cosine), 5);

                    if (reflectance > rand(seed)) {
                        dir -= norm * dot(norm, dir)*2;
                    } else {
                        dir = refract(dir, norm, eta);
                    }
                } else {
                    // Otherwise, we're exiting the shape and need to check
                    // for total internal reflection
                    vec3 next_dir = refract(dir, -norm, eta);
                    // If we can't refract, then reflect instead
                    if (next_dir == vec3(0)) {
                        dir -= norm * dot(norm, dir)*2;
                    } else {
                        dir = next_dir;
                    }
                }
                break;
        }
    }
    // If we couldn't reach a light in max bounces, return black
    return vec3(0);
}

////////////////////////////////////////////////////////////////////////////////

void main() {
    // Set up our random seed based on the frame and pixel position
    uint seed = hash(hash(hash(u.samples) ^ floatBitsToUint(gl_FragCoord.x))
                                          ^ floatBitsToUint(gl_FragCoord.y));
    fragColor = vec4(0);

    for (uint i=0; i < u.samples_per_frame; ++i) {
        // Add anti-aliasing by jittering within the pixel
        float dx = rand(seed);
        float dy = rand(seed);

        vec2 pixel_pos = gl_FragCoord.xy + vec2(dx, dy);
        vec2 xy = 2*pixel_pos / vec2(u.width_px, u.height_px) - 1;

        vec4 start = vec4(xy, 1, 0);
#define USE_PERSPECTIVE 1
#if USE_PERSPECTIVE
        vec3 dir = normalize(vec3(xy/3, -1));
#else
        vec3 dir = vec3(0, 0, -1);
#endif

        fragColor += vec4(bounce(start, dir, seed), 1);
    }
}
