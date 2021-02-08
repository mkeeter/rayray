# rayray
A tiny GPU raytracer!

(more details on the [project homepage](https://www.mattkeeter.com/projects/rayray))

![Cornell Box](https://www.mattkeeter.com/projects/rayray/renders/cornell@2x.png)

![Ray tracing in one weekend](https://www.mattkeeter.com/projects/rayray/renders/rtiow@2x.png)

## Features
- Diffuse, metal, and glass materials
- The only three shapes that matter:
    - Spheres
    - Planes (both infinite and finite)
    - Cylinders (both infinite and capped)
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

## Project status
![Project unsupported](https://img.shields.io/badge/project-unsupported-red.svg)

This is a personal / toy project,
and I don't plan to support it on anything other than my laptop
(macOS 10.13, `zig-macos-x86_64-0.8.0-dev.1125`,
and `wgpu-native` built from source).

I'm unlikely to fix any issues,
although I will optimistically merge small-to-medium PRs that fix bugs
or add support for more platforms.

That being said, I'm generally friendly,
so feel free to open issues and ask questions;
just don't set your expectations too high!

If you'd like to add major features, please fork the project;
I'd be happy to link to any forks which achieve critical momemtum!

## License
Licensed under either of

 * [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0)
 * [MIT license](http://opensource.org/licenses/MIT)

at your option.

## Contribution
Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.
