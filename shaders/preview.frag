#version 440
#pragma shader_stage(fragment)
#include "shaders/rt_core.frag"

layout(set=0, binding=1) buffer Scene {
    vec4[] scene_data;
};

vec3 norm(vec3 pos, uvec4 shape) {
    uint offset = shape.y;
    switch (shape.x) {
        case SHAPE_SPHERE: {
            vec4 d = scene_data[offset];
            return norm_sphere(pos, d.xyz);
        }
        case SHAPE_INFINITE_PLANE: // fallthrough
        case SHAPE_FINITE_PLANE: {
            vec4 d = scene_data[offset];
            return norm_plane(pos, d.xyz);
        }
        default: // unimplemented
            return vec3(0);
    }
}

////////////////////////////////////////////////////////////////////////////////
// The lowest-level building block:
//  Raytraces to the next object in the scene,
//  returning a hit_t object of [pos, index]
uint trace(inout vec3 start, vec3 dir) {
    float best_dist = 1e8;
    uint best_hit = 0;
    const uint num_shapes = floatBitsToUint(scene_data[0].x);

    for (uint i=1; i <= num_shapes; i += 1) {
        uvec4 shape = floatBitsToUint(scene_data[i]);
        uint offset = shape.y;
        float dist;
        switch (shape.x) {
            case SHAPE_SPHERE: {
                vec4 d = scene_data[offset];
                dist = hit_sphere(start, dir, d.xyz, d.w);
                break;
            }
            case SHAPE_INFINITE_PLANE: {
                vec4 d = scene_data[offset];
                dist = hit_plane(start, dir, d.xyz, d.w);
                break;
            }
            default: // unimplemented shape
                continue;
        }
        if (dist > SURFACE_EPSILON && dist < best_dist) {
            best_dist = dist;
            best_hit = i;
        }
    }
    if (best_hit != 0) {
        start = start + dir*best_dist;
    }
    return best_hit;
}

bool mat(inout uint seed, inout vec3 color, inout vec3 dir,
         uint index, vec3 pos)
{
    // Extract the shape so we can pull the material
    uvec4 shape = floatBitsToUint(scene_data[index]);
    vec3 norm = norm(pos, shape);

    // Look at the material and decide whether to terminate
    uint mat_offset = shape.z;
    uint mat_type = shape.w;

    switch (mat_type) {
        // When we hit a light, return immediately
        case MAT_LIGHT:
            color *= scene_data[mat_offset].xyz;
            return true;

        // Otherwise, handle the various material types
        case MAT_DIFFUSE:
            mat_diffuse(seed, color, dir, norm, scene_data[mat_offset].xyz);
            break;
        case MAT_METAL:
            mat_metal(seed, color, dir, norm, scene_data[mat_offset].xyz,
                    scene_data[mat_offset].w);
            break;
        case MAT_GLASS:
            mat_glass(seed, color, dir, norm, scene_data[mat_offset].w);
            break;
    }
    return false;
}
