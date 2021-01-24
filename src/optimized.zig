const std = @import("std");

const c = @import("c.zig");
const shaderc = @import("shaderc.zig");

// This struct runs a raytracing kernel which uses a compiled scene.
// Compiling the scene shader is slower to generate initially, but runs faster.
pub const Optimized = struct {
    const Self = @This();

    bind_group: c.WGPUBindGroupId,
    render_pipeline: c.WGPURenderPipelineId,

    pub fn init(
        alloc: *std.mem.Allocator,
        frag_shader: c.WGPUShaderModuleId,
        device: c.WGPUDeviceId,
        uniform_buf: c.WGPUBufferId,
    ) !Self {
        var arena = std.heap.ArenaAllocator.init(alloc);
        const tmp_alloc: *std.mem.Allocator = &arena.allocator;
        defer arena.deinit();

        // Build the vertex shader using shaderc
        // (TODO: this could be shared with preview.zig)
        const rt_vert_name = "shaders/raytrace.vert";
        const vert_spv = try shaderc.build_shader_from_file(tmp_alloc, rt_vert_name);
        const vert_shader = c.wgpu_device_create_shader_module(
            device,
            &(c.WGPUShaderModuleDescriptor){
                .label = rt_vert_name,
                .bytes = vert_spv.ptr,
                .length = vert_spv.len,
                .flags = c.WGPUShaderFlags_VALIDATION,
            },
        );
        defer c.wgpu_shader_module_destroy(vert_shader);

        ////////////////////////////////////////////////////////////////////////////
        // Bind groups
        const bind_group_layout_entries = [_]c.WGPUBindGroupLayoutEntry{
            (c.WGPUBindGroupLayoutEntry){ // Uniforms buffer
                .binding = 0,
                .visibility = c.WGPUShaderStage_FRAGMENT,
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
        };
        const bind_group_layout = c.wgpu_device_create_bind_group_layout(
            device,
            &(c.WGPUBindGroupLayoutDescriptor){
                .label = "bind group layout",
                .entries = &bind_group_layout_entries,
                .entries_length = bind_group_layout_entries.len,
            },
        );
        defer c.wgpu_bind_group_layout_destroy(bind_group_layout);
        const bind_group_layouts = [_]c.WGPUBindGroupId{bind_group_layout};

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
        };
        const bind_group = c.wgpu_device_create_bind_group(
            device,
            &(c.WGPUBindGroupDescriptor){
                .label = "bind group",
                .layout = bind_group_layout,
                .entries = &bind_group_entries,
                .entries_length = bind_group_entries.len,
            },
        );

        ////////////////////////////////////////////////////////////////////////
        // Render pipelines
        const pipeline_layout = c.wgpu_device_create_pipeline_layout(
            device,
            &(c.WGPUPipelineLayoutDescriptor){
                .label = "",
                .bind_group_layouts = &bind_group_layouts,
                .bind_group_layouts_length = bind_group_layouts.len,
            },
        );
        defer c.wgpu_pipeline_layout_destroy(pipeline_layout);

        const render_pipeline = c.wgpu_device_create_render_pipeline(
            device,
            &(c.WGPURenderPipelineDescriptor){
                .label = "preview pipeline",
                .layout = pipeline_layout,
                .vertex_stage = (c.WGPUProgrammableStageDescriptor){
                    .module = vert_shader,
                    .entry_point = "main",
                },
                .fragment_stage = &(c.WGPUProgrammableStageDescriptor){
                    .module = frag_shader,
                    .entry_point = "main",
                },
                .rasterization_state = &(c.WGPURasterizationStateDescriptor){
                    .front_face = c.WGPUFrontFace._Ccw,
                    .cull_mode = c.WGPUCullMode._None,
                    .polygon_mode = c.WGPUPolygonMode._Fill,
                    .clamp_depth = false,
                    .depth_bias = 0,
                    .depth_bias_slope_scale = 0.0,
                    .depth_bias_clamp = 0.0,
                },
                .primitive_topology = c.WGPUPrimitiveTopology._TriangleList,
                .color_states = &(c.WGPUColorStateDescriptor){
                    .format = c.WGPUTextureFormat._Rgba32Float,
                    .alpha_blend = (c.WGPUBlendDescriptor){
                        .src_factor = c.WGPUBlendFactor._One,
                        .dst_factor = c.WGPUBlendFactor._Zero,
                        .operation = c.WGPUBlendOperation._Add,
                    },
                    .color_blend = (c.WGPUBlendDescriptor){
                        .src_factor = c.WGPUBlendFactor._One,
                        .dst_factor = c.WGPUBlendFactor._One,
                        .operation = c.WGPUBlendOperation._Add,
                    },
                    .write_mask = c.WGPUColorWrite_ALL,
                },
                .color_states_length = 1,
                .depth_stencil_state = null,
                .vertex_state = (c.WGPUVertexStateDescriptor){
                    .index_format = c.WGPUIndexFormat_Undefined,
                    .vertex_buffers = null,
                    .vertex_buffers_length = 0,
                },
                .sample_count = 1,
                .sample_mask = 0,
                .alpha_to_coverage = false,
            },
        );

        ////////////////////////////////////////////////////////////////////////
        var out = Self{
            .bind_group = bind_group,
            .render_pipeline = render_pipeline,
        };
        return out;
    }

    pub fn deinit(self: *Self) void {
        c.wgpu_bind_group_destroy(self.bind_group);
        c.wgpu_render_pipeline_destroy(self.render_pipeline);
    }

    pub fn draw(
        self: *Self,
        first: bool,
        tex_view: c.WGPUTextureViewId,
        cmd_encoder: c.WGPUCommandEncoderId,
    ) !void {
        const load_op = if (first)
            c.WGPULoadOp._Clear
        else
            c.WGPULoadOp._Load;
        const color_attachments = [_]c.WGPUColorAttachmentDescriptor{
            (c.WGPUColorAttachmentDescriptor){
                .attachment = tex_view,
                .resolve_target = 0,
                .channel = (c.WGPUPassChannel_Color){
                    .load_op = load_op,
                    .store_op = c.WGPUStoreOp._Store,
                    .clear_value = (c.WGPUColor){
                        .r = 0.0,
                        .g = 0.0,
                        .b = 0.0,
                        .a = 1.0,
                    },
                    .read_only = false,
                },
            },
        };

        const rpass = c.wgpu_command_encoder_begin_render_pass(
            cmd_encoder,
            &(c.WGPURenderPassDescriptor){
                .label = "optimized render pass",
                .color_attachments = &color_attachments,
                .color_attachments_length = color_attachments.len,
                .depth_stencil_attachment = null,
            },
        );

        c.wgpu_render_pass_set_pipeline(rpass, self.render_pipeline);
        c.wgpu_render_pass_set_bind_group(rpass, 0, self.bind_group, null, 0);
        c.wgpu_render_pass_draw(rpass, 3, 1, 0, 0);
        c.wgpu_render_pass_end_pass(rpass);
    }
};
