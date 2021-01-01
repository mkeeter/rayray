#version 440
#pragma shader_stage(fragment)
#include "extern/rayray.h"

layout(location=0) out vec4 fragColor;

layout(set=0, binding=0, std430) uniform Uniforms {
    raytraceUniforms u;
};
layout(set=0, binding=1) buffer Scene {
    uint[] scene_data;
};

void main()  {
    fragColor = vec4(0.01, 0, 0, 1);
}
