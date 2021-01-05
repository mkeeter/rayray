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

#define SHAPE_NONE 0
#define SHAPE_SPHERE 1
#define SHAPE_INFINITE_PLANE 2
#define SHAPE_FINITE_PLANE 3

#define MAT_NONE 0
#define MAT_DIFFUSE 1
#define MAT_LIGHT 2
#define MAT_METAL 3
#define MAT_GLASS 4

////////////////////////////////////////////////////////////////////////////////

struct rayUniforms {
    uint32_t width_px;
    uint32_t height_px;

    uint32_t samples; // Used to scale brightness
    uint32_t samples_per_frame; // Loop in the fragment shader on faster GPUs

    float perspective; // How much perspective to apply
    float focal_distance; // Distance to the point of perfect focus
    float defocus;  // Amount to jitter ray sources
};
