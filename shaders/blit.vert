#version 450
#pragma shader_stage(vertex)

void main() {
    switch (gl_VertexIndex) {
        case 0: gl_Position = vec4(-1, -1, 0, 1); break;
        case 1: gl_Position = vec4(-1, 3, 0, 1); break;
        case 2: gl_Position = vec4(3, -1, 0, 1); break;
        default: gl_Position = vec4(0); break; // invalid
    }
}
