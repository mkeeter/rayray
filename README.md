# rayray
A tiny GPU raytracer!

![Cornell Box](https://www.mattkeeter.com/projects/rayray/cornell@2x.png)

![Ray tracing in one weekend](https://www.mattkeeter.com/projects/rayray/rtiow@2x.png)

## Features
- Diffuse, metal, and glass materials
- The only two shapes that matter:
    - Spheres
    - Infinite planes
- Any shape can be a light!
- Antialiasing with sub-pixel sampling
- Will **crash your entire computer** if you render too many rays per frame
  (thanks, GPU drivers)

## Implementation
- Built on the bones of [Futureproof](https://mattkeeter.com/projects/futureproof)
- Written in [Zig](https://ziglang.org)
- Using [WebGPU](https://gpuweb.github.io/gpuweb/) for graphics
  via [`wgpu-native`](https://github.com/gfx-rs/wgpu-native)
- Shaders compiled from GLSL to SPIR-V with [`shaderc`](https://github.com/google/shaderc)
- Minimal GUI using [Dear ImGUI](https://github.com/ocornut/imgui),
  with a custom [Zig + WebGPU backend](https://github.com/mkeeter/rayray/blob/master/src/gui/backend.zig)
- Vaguely based on [_Ray Tracing in One Weekend_](https://raytracing.github.io/books/RayTracingInOneWeekend.html),
  with a data-driven design to run on the GPU.
