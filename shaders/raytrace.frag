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

////////////////////////////////////////////////////////////////////////////////
// RNGs
// http://byteblacksmith.com/improvements-to-the-canonical-one-liner-glsl-rand-for-opengl-es-2-0/
float rand(vec2 co) {
    float a = 12.9898;
    float b = 78.233;
    float c = 43758.5453;
    float dt = dot(co.xy, vec2(a, b));
    float sn = mod(dt, 3.1415926);
    return fract(sin(sn) * c);
}

// Single-round randomization, which will show patterns in many cases
vec3 rand3_(vec3 seed) {
    float a = rand(vec2(seed.z, rand(seed.xy)));
    float b = rand(vec2(seed.y, rand(seed.xz)));
    float c = rand(vec2(seed.x, rand(seed.yz)));
    return vec3(a, b, c);
}

// Two-round randomization, which is closer to uniform
vec3 rand3(vec3 seed) {
    return rand3_(rand3_(seed));
}

vec3 rand3_sphere(vec3 seed) {
    while (true) {
        vec3 v = rand3(seed)*2 - 1;
        if (length(v) <= 1.0) {
            return normalize(v);
        }
        seed += vec3(0.1, 1, 10);
    }
}

void main() {
    vec2 pos = gl_FragCoord.xy / vec2(u.width_px, u.height_px);

    fragColor = vec4(rand3_sphere(vec3(pos, u.frame)), 1);
}
