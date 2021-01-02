#version 450
#pragma shader_stage(vertex)

layout(location=0) out vec2 v_tex_coords;

void main() {
    switch (gl_VertexIndex) {
        case 0: v_tex_coords = vec2(0, 0); break;
        case 1: v_tex_coords = vec2(0, 2); break;
        case 2: v_tex_coords = vec2(2, 0); break;
        default: v_tex_coords = vec2(0); break; // invalid
    }
    gl_Position = vec4(v_tex_coords * 2 - 1, 0, 1);
}
