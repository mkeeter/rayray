#version 440
#pragma shader_stage(fragment)
#include "shaders/rt_core.frag"

layout(set=0, binding=1) buffer Scene {
    vec4[] scene_data;
};

////////////////////////////////////////////////////////////////////////////////
// The lowest-level building block:
//  Raytraces to the next object in the scene, updating state variables.
//  Returns true if we should terminate, false otherwise
bool trace(inout uint seed, inout vec3 pos, inout vec3 dir, inout vec3 color) {
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
                dist = hit_sphere(pos, dir, d.xyz, d.w);
                break;
            }
            case SHAPE_INFINITE_PLANE: {
                vec4 d = scene_data[offset];
                dist = hit_plane(pos, dir, d.xyz, d.w);
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

    // If we missed all objects, terminate immediately with blackness
    if (best_hit == 0) {
        color = vec3(0);
        return true;
    }
    pos = pos + dir*best_dist;

    // Extract the shape, then compute its normal and material
    uvec4 shape = floatBitsToUint(scene_data[best_hit]);
    uint offset = shape.y;
    vec3 norm = vec3(0);
    switch (shape.x) {
        case SHAPE_SPHERE: {
            vec4 d = scene_data[offset];
            norm = norm_sphere(pos, d.xyz);
            break;
        }
        case SHAPE_INFINITE_PLANE: { // fallthrough
            vec4 d = scene_data[offset];
            norm = norm_plane(d.xyz);
            break;
        }
    }

    // Look at the material and decide whether to terminate
    uint mat_offset = shape.z;
    uint mat_type = shape.w;

    switch (mat_type) {
        // When we hit a light, return immediately
        case MAT_LIGHT:
            return mat_light(color, scene_data[mat_offset].xyz);

        // Otherwise, handle the various material types
        case MAT_DIFFUSE:
            return mat_diffuse(seed, color, dir, norm, scene_data[mat_offset].xyz);
        case MAT_METAL:
            return mat_metal(seed, color, dir, norm, scene_data[mat_offset].xyz,
                             scene_data[mat_offset].w);
        case MAT_GLASS:
            return mat_glass(seed, color, dir, norm, scene_data[mat_offset].w);
    }

    // Reaching here is an error, so set the color to green and terminate
    color = vec3(0, 1, 0);
    return true;
}
