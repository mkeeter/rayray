#version 450
#pragma shader_stage(vertex)
#include "extern/rayray.h"

layout(location=0) in vec2 position;
layout(location=1) in vec2 uv;
layout(location=2) in vec4 color;

layout(set=0, binding=0) uniform Uniforms {
    mat4 proj_mtx;
};

layout(location=0) out vec2 frag_uv;
layout(location=1) out vec4 frag_color;

void main() {
    frag_uv = uv;
    frag_color = color;
    gl_Position = proj_mtx * vec4(position.xy, 0, 1);
}
