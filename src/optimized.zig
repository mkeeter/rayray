const std = @import("std");

const c = @import("c.zig");
const shaderc = @import("shaderc.zig");

// This struct runs a raytracing kernel which uses a compiled scene.
// Compiling the scene shader is slower to generate initially, but runs faster.
pub const Optimized = struct {
    const Self = @This();

    device: c.WGPUDeviceId,

    bind_group: c.WGPUBindGroupId,
    bind_group_layout: c.WGPUBindGroupLayoutId,

    compute_pipeline: c.WGPURenderPipelineId,

    initialized: bool = false,

    pub fn init(
        alloc: *std.mem.Allocator,
        comp_shader: c.WGPUShaderModuleId,
        device: c.WGPUDeviceId,
        uniform_buf: c.WGPUBufferId,
        tex_view: c.WGPUTextureViewId,
    ) !Self {
        var arena = std.heap.ArenaAllocator.init(alloc);
        const tmp_alloc: *std.mem.Allocator = &arena.allocator;
        defer arena.deinit();

        ////////////////////////////////////////////////////////////////////////////
        // Bind groups
        const bind_group_layout_entries = [_]c.WGPUBindGroupLayoutEntry{
            (c.WGPUBindGroupLayoutEntry){ // Uniforms buffer
                .binding = 0,
                .visibility = c.WGPUShaderStage_COMPUTE,
                .ty = c.WGPUBindingType_UniformBuffer,

                .has_dynamic_offset = false,
                .min_buffer_binding_size = 0,

                .multisampled = undefined,
                .filtering = undefined,
                .view_dimension = undefined,
                .texture_component_type = undefined,
                .storage_texture_format = undefined,
                .count = undefined,
            },
            (c.WGPUBindGroupLayoutEntry){ // Output image
                .binding = 1,
                .visibility = c.WGPUShaderStage_COMPUTE,
                .ty = c.WGPUBindingType_WriteonlyStorageTexture,

                .storage_texture_format = c.WGPUTextureFormat._Rgba32Float,
                .view_dimension = c.WGPUTextureViewDimension._D2,

                .has_dynamic_offset = undefined,
                .min_buffer_binding_size = undefined,

                .multisampled = undefined,
                .texture_component_type = undefined,
                .count = undefined,
                .filtering = undefined,
            },
        };
        const bind_group_layout = c.wgpu_device_create_bind_group_layout(
            device,
            &(c.WGPUBindGroupLayoutDescriptor){
                .label = "bind group layout",
                .entries = &bind_group_layout_entries,
                .entries_length = bind_group_layout_entries.len,
            },
        );

        ////////////////////////////////////////////////////////////////////////
        // Render pipelines
        const bind_group_layouts = [_]c.WGPUBindGroupId{bind_group_layout};
        const pipeline_layout = c.wgpu_device_create_pipeline_layout(
            device,
            &(c.WGPUPipelineLayoutDescriptor){
                .label = "",
                .bind_group_layouts = &bind_group_layouts,
                .bind_group_layouts_length = bind_group_layouts.len,
            },
        );
        defer c.wgpu_pipeline_layout_destroy(pipeline_layout);

        const compute_pipeline = c.wgpu_device_create_compute_pipeline(
            device,
            &(c.WGPUComputePipelineDescriptor){
                .label = "preview pipeline",
                .layout = pipeline_layout,
                .compute_stage = (c.WGPUProgrammableStageDescriptor){
                    .module = comp_shader,
                    .entry_point = "main",
                },
            },
        );

        ////////////////////////////////////////////////////////////////////////
        var out = Self{
            .device = device,
            .bind_group = undefined, // populated in rebuilds_bind_group
            .bind_group_layout = bind_group_layout,
            .compute_pipeline = compute_pipeline,
        };
        out.rebuild_bind_group(uniform_buf, tex_view);
        out.initialized = true;
        return out;
    }

    pub fn rebuild_bind_group(
        self: *Self,
        uniform_buf: c.WGPUBufferId,
        tex_view: c.WGPUTextureViewId,
    ) void {
        if (self.initialized) {
            c.wgpu_bind_group_destroy(self.bind_group);
        }
        // Rebuild the bind group as well
        const bind_group_entries = [_]c.WGPUBindGroupEntry{
            (c.WGPUBindGroupEntry){
                .binding = 0,
                .buffer = uniform_buf,
                .offset = 0,
                .size = @sizeOf(c.rayUniforms),

                .sampler = 0, // None
                .texture_view = 0, // None
            },
            (c.WGPUBindGroupEntry){
                .binding = 1,
                .texture_view = tex_view,
                .buffer = 0, // None
                .sampler = 0, // None

                .offset = undefined,
                .size = undefined,
            },
        };
        self.bind_group = c.wgpu_device_create_bind_group(
            self.device,
            &(c.WGPUBindGroupDescriptor){
                .label = "bind group",
                .layout = self.bind_group_layout,
                .entries = &bind_group_entries,
                .entries_length = bind_group_entries.len,
            },
        );
    }

    pub fn deinit(self: *Self) void {
        c.wgpu_bind_group_layout_destroy(self.bind_group_layout);
        c.wgpu_bind_group_destroy(self.bind_group);
        c.wgpu_compute_pipeline_destroy(self.compute_pipeline);
    }

    pub fn render(
        self: *Self,
        first: bool,
        nx: u32,
        ny: u32,
        cmd_encoder: c.WGPUCommandEncoderId,
    ) !void {
        const cpass = c.wgpu_command_encoder_begin_compute_pass(
            cmd_encoder,
            &(c.WGPUComputePassDescriptor){ .label = "" },
        );

        c.wgpu_compute_pass_set_pipeline(cpass, self.compute_pipeline);
        c.wgpu_compute_pass_set_bind_group(cpass, 0, self.bind_group, null, 0);
        c.wgpu_compute_pass_dispatch(cpass, nx, ny, 1);
        c.wgpu_compute_pass_end_pass(cpass);
    }
};
