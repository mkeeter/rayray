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

////////////////////////////////////////////////////////////////////////////////

struct raytraceUniforms {
    uint32_t width_px;
    uint32_t height_px;
};

struct blitUniforms {
    uint32_t samples;
};
