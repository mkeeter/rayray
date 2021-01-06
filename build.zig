const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("rayray", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    // Libraries!
    exe.linkSystemLibrary("glfw3");
    exe.linkSystemLibrary("stdc++"); // needed for shaderc

    exe.addLibPath("vendor/wgpu");
    exe.linkSystemLibrary("wgpu_native");
    exe.addIncludeDir("vendor"); // "wgpu/wgpu.h" is the wgpu header

    exe.addLibPath("vendor/shaderc/lib");
    exe.linkSystemLibrary("shaderc_combined");
    exe.addIncludeDir("vendor/shaderc/include/");

    exe.addIncludeDir("."); // for "extern/rayray.h"

    const c_args = [_][]const u8{
        "-O3",
    };
    const imgui_files = [_][]const u8{
        "vendor/cimgui/cimgui.cpp",
        "vendor/cimgui/imgui/imgui.cpp",
        "vendor/cimgui/imgui/imgui_draw.cpp",
        "vendor/cimgui/imgui/imgui_demo.cpp",
        "vendor/cimgui/imgui/imgui_widgets.cpp",
    };
    exe.addCSourceFiles(&imgui_files, &c_args);

    exe.install();

    if (exe.target.isDarwin()) {
        exe.addFrameworkDir("/System/Library/Frameworks");
        exe.linkFramework("Foundation");
        exe.linkFramework("AppKit");
    }

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
