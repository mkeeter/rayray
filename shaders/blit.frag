#version 450
#pragma shader_stage(fragment)
#include "extern/rayray.h"

layout(location=0) in vec2 v_tex_coords;

layout(set=0, binding=0) uniform texture2D raytrace_tex;
layout(set=0, binding=1) uniform sampler raytrace_sampler;
layout(set=0, binding=2, std430) uniform Uniforms {
    rayUniforms u;
};

layout(location=0) out vec4 out_color;

void main() {
    float scale = 1.0 / (u.samples + u.samples_per_frame);
    //out_color = sqrt(scale * texture(sampler2D(raytrace_tex, raytrace_sampler), v_tex_coords));
    out_color = texture(sampler2D(raytrace_tex, raytrace_sampler), v_tex_coords);
}
