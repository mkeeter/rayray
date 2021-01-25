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
        image_buf: c.WGPUTextureViewId,
        image_buf_size: u32,
    ) !Self {
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
            (c.WGPUBindGroupLayoutEntry){ // Image buffer
                .binding = 1,
                .visibility = c.WGPUShaderStage_COMPUTE,
                .ty = c.WGPUBindingType_StorageBuffer,

                .has_dynamic_offset = false,
                .min_buffer_binding_size = 0,

                .multisampled = undefined,
                .filtering = undefined,
                .view_dimension = undefined,
                .texture_component_type = undefined,
                .storage_texture_format = undefined,
                .count = undefined,
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
        out.rebuild_bind_group(uniform_buf, image_buf, image_buf_size);
        out.initialized = true;
        return out;
    }

    pub fn rebuild_bind_group(
        self: *Self,
        uniform_buf: c.WGPUBufferId,
        image_buf: c.WGPUBufferId,
        image_buf_size: u32,
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
                .buffer = image_buf,
                .offset = 0,
                .size = image_buf_size,

                .sampler = 0, // None
                .texture_view = 0, // None
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
        nt: u32,
        cmd_encoder: c.WGPUCommandEncoderId,
    ) !void {
        const cpass = c.wgpu_command_encoder_begin_compute_pass(
            cmd_encoder,
            &(c.WGPUComputePassDescriptor){ .label = "" },
        );

        c.wgpu_compute_pass_set_pipeline(cpass, self.compute_pipeline);
        c.wgpu_compute_pass_set_bind_group(cpass, 0, self.bind_group, null, 0);
        c.wgpu_compute_pass_dispatch(cpass, nt, 1, 1);
        c.wgpu_compute_pass_end_pass(cpass);
    }
};
