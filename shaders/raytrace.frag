#version 440
#pragma shader_stage(fragment)
#extension GL_EXT_scalar_block_layout : require
#include "extern/futureproof.h"

layout(location=0) out vec4 fragColor;

layout(set=0, binding=2, std430) uniform Uniforms {
    fpUniforms u;
};
layout(set=0, binding=3) buffer Scene {
    uint[] scene_data;
};

void main()  {
    fragColor = vec4(1, 0, 0, 1);
}
