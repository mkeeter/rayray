#version 450
#pragma shader_stage(vertex)
#extension GL_EXT_scalar_block_layout : require

void main() {
    vec2 pos;
    switch (gl_VertexIndex) {
        case 0: pos = vec2(0, 1); break;
        case 1: pos = vec2(0, 0); break;
        case 2: pos = vec2(1, 0); break;
        case 3: pos = vec2(0, 1); break;
        case 4: pos = vec2(1, 0); break;
        case 5: pos = vec2(1, 1); break;
        default: pos = vec2(0); break; // invalid
    }
    gl_Position = vec4(pos*2 - 1, 0, 1);
}
