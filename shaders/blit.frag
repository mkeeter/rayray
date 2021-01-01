#version 450
#pragma shader_stage(fragment)
#include "extern/rayray.h"

layout(location=0) in vec2 v_tex_coords;

layout(set=0, binding=0) uniform texture2D raytrace_tex;
layout(set=0, binding=1) uniform sampler raytrace_sampler;
layout(set=0, binding=2, std430) uniform Uniforms {
    blitUniforms u;
};

layout(location=0) out vec4 out_color;

void main() {
    out_color = texture(sampler2D(raytrace_tex, raytrace_sampler), v_tex_coords);
}
