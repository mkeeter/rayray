#version 450
#pragma shader_stage(vertex)

void main() {
    vec2 pos;
    switch (gl_VertexIndex) {
        case 0: pos = vec2(0, 0); break;
        case 1: pos = vec2(0, 2); break;
        case 2: pos = vec2(2, 0); break;
        default: pos = vec2(0); break; // invalid
    }
    gl_Position = vec4(pos*2 - 1, 0, 1);
}
