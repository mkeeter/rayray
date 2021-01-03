# rayray
A tiny GPU raytracer!

## Features
- Diffuse, metal, and glass materials
- The only two shapes that matter:
    - Spheres
    - Infinite planes
- Any shape can be a light!
- Antialiasing with sub-pixel sampling
- Will crash your entire computer if you render too many rays per frame
  (thanks, GPU drivers)

## Implementation
- Built on the bones of [Futureproof](https://mattkeeter.com/projects/futureproof)
- Written in [Zig](https://ziglang.org)
- Using [WebGPU](https://gpuweb.github.io/gpuweb/) for graphics
  via [`wgpu-native`](https://github.com/gfx-rs/wgpu-native)
- Shaders compiled from GLSL to SPIR-V with [`shaderc`](https://github.com/google/shaderc)
- Slightly based on [_Ray Tracing in One Weekend_](https://raytracing.github.io/books/RayTracingInOneWeekend.html),
  but using a data-driven design to run on the GPU.
