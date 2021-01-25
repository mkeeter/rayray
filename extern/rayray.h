// This block allows headers to work around missing sized integer type
// (in GLSL), vec types (in C), and slightly different handling of struct
// naming (using the MEMBER_STRUCT macro).

#if GL_core_profile // Compiling as GLSL
#define uint32_t uint
#define int32_t int
#define MEMBER_STRUCT
#extension GL_EXT_scalar_block_layout : require

#else // Compiling as a C header file
#pragma once
#include <stdint.h>
#define MEMBER_STRUCT struct
typedef struct {
    float x, y, z;
} vec3;
typedef struct {
    float x, y, z, w;
} vec4;
#endif

// Size of compute shader thread-group (run as a 1D shader)
#define COMPUTE_SIZE 64

#define SHAPE_NONE 0
#define SHAPE_SPHERE 1
#define SHAPE_INFINITE_PLANE 2
#define SHAPE_FINITE_PLANE 3
#define LAST_SHAPE 4

#define MAT_NONE 0
#define MAT_DIFFUSE 1
#define MAT_LIGHT 2
#define MAT_METAL 3
#define MAT_GLASS 4
#define LAST_MAT 5

////////////////////////////////////////////////////////////////////////////////

struct rayCamera {
    // Order matters here: we alternate between vec3 and float because a vec3
    // has a minimum alignment of 4, so this ensures that the CPU and GPU both
    // pack the struct correctly
    vec3 pos;
    float scale; // Half-size of sensor at camera_pos
    vec3 target;
    float defocus; // Amount to jitter ray origins
    vec3 up;
    float perspective;
    float focal_distance;
};

struct rayUniforms {
    uint32_t width_px;
    uint32_t height_px;

    uint32_t offset_x;
    uint32_t offset_y;

    uint32_t samples; // Used to scale brightness
    uint32_t samples_per_frame; // Loop in the fragment shader on faster GPUs

    uint32_t _padding[2];

    // Camera parameters!
    MEMBER_STRUCT rayCamera camera;
};
