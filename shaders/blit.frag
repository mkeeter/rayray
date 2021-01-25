#version 450
#pragma shader_stage(fragment)
#include "extern/rayray.h"

layout(set=0, binding=0) buffer Image {
    vec4[] image;
};
layout(set=0, binding=1, std430) uniform Uniforms {
    rayUniforms u;
};

layout(location=0) out vec4 out_color;

void main() {
    float scale = 1.0 / (u.samples + u.samples_per_frame);
    uvec2 p = uvec2(gl_FragCoord.xy) - uvec2(u.offset_x, u.offset_y);
    p.y = u.height_px - p.y - 1;
    out_color = sqrt(scale * image[p.x + p.y * u.width_px]);
}
