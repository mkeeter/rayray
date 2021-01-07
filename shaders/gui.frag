#version 450
#pragma shader_stage(fragment)

layout(location=0) in vec2 frag_uv;
layout(location=1) in vec4 frag_color;

layout(set=0, binding=0) uniform texture2D tex;
layout(set=0, binding=1) uniform sampler tex_sampler;

layout(location=0) out vec4 out_color;

void main() {
    out_color = frag_color * texture(sampler2D(tex, tex_sampler), frag_uv);
}
