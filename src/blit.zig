const std = @import("std");

const c = @import("c.zig");
const shaderc = @import("shaderc.zig");

pub const Blit = struct {
    const Self = @This();

    device: c.WGPUDeviceId,
    queue: c.WGPUQueueId,

    bind_group_layout: c.WGPUBindGroupLayoutId,
    tex_sampler: c.WGPUSamplerId,
    bind_group: c.WGPUBindGroupId,

    render_pipeline: c.WGPURenderPipelineId,

    pub fn init(
        alloc: *std.mem.Allocator,
        device: c.WGPUDeviceId,
        tex_view: c.WGPUTextureViewId,
        uniform_buf: c.WGPUBufferId,
    ) !Blit {
        var arena = std.heap.ArenaAllocator.init(alloc);
        const tmp_alloc: *std.mem.Allocator = &arena.allocator;
        defer arena.deinit();

        ////////////////////////////////////////////////////////////////////////////
        // Build the shaders using shaderc
        const vert_spv = shaderc.build_shader_from_file(tmp_alloc, "shaders/blit.vert") catch |err| {
            std.debug.panic("Could not open file", .{});
        };
        const vert_shader = c.wgpu_device_create_shader_module(
            device,
            (c.WGPUShaderSource){
                .bytes = vert_spv.ptr,
                .length = vert_spv.len,
            },
        );
        defer c.wgpu_shader_module_destroy(vert_shader);

        const frag_spv = shaderc.build_shader_from_file(tmp_alloc, "shaders/blit.frag") catch |err| {
            std.debug.panic("Could not open file", .{});
        };
        const frag_shader = c.wgpu_device_create_shader_module(
            device,
            (c.WGPUShaderSource){
                .bytes = frag_spv.ptr,
                .length = frag_spv.len,
            },
        );
        defer c.wgpu_shader_module_destroy(frag_shader);

        ///////////////////////////////////////////////////////////////////////
        // Texture sampler (the texture comes from the Preview struct)
        const tex_sampler = c.wgpu_device_create_sampler(device, &(c.WGPUSamplerDescriptor){
            .next_in_chain = null,
            .label = "tex_sampler",
            .address_mode_u = c.WGPUAddressMode._ClampToEdge,
            .address_mode_v = c.WGPUAddressMode._ClampToEdge,
            .address_mode_w = c.WGPUAddressMode._ClampToEdge,
            .mag_filter = c.WGPUFilterMode._Linear,
            .min_filter = c.WGPUFilterMode._Nearest,
            .mipmap_filter = c.WGPUFilterMode._Nearest,
            .lod_min_clamp = 0.0,
            .lod_max_clamp = std.math.f32_max,
            .compare = c.WGPUCompareFunction._Undefined,
        });

        ////////////////////////////////////////////////////////////////////////////
        // Bind groups
        const bind_group_layout_entries = [_]c.WGPUBindGroupLayoutEntry{
            (c.WGPUBindGroupLayoutEntry){
                .binding = 0,
                .visibility = c.WGPUShaderStage_FRAGMENT,
                .ty = c.WGPUBindingType_SampledTexture,

                .multisampled = false,
                .view_dimension = c.WGPUTextureViewDimension._D2,
                .texture_component_type = c.WGPUTextureComponentType._Float,
                .storage_texture_format = c.WGPUTextureFormat._Rgba32Float,

                .count = undefined,
                .has_dynamic_offset = undefined,
                .min_buffer_binding_size = undefined,
            },
            (c.WGPUBindGroupLayoutEntry){
                .binding = 1,
                .visibility = c.WGPUShaderStage_FRAGMENT,
                .ty = c.WGPUBindingType_Sampler,

                .multisampled = undefined,
                .view_dimension = undefined,
                .texture_component_type = undefined,
                .storage_texture_format = undefined,
                .count = undefined,
                .has_dynamic_offset = undefined,
                .min_buffer_binding_size = undefined,
            },
            (c.WGPUBindGroupLayoutEntry){ // Uniforms buffer
                .binding = 2,
                .visibility = c.WGPUShaderStage_FRAGMENT,
                .ty = c.WGPUBindingType_UniformBuffer,

                .has_dynamic_offset = false,
                .min_buffer_binding_size = 0,

                .multisampled = undefined,
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
        const bind_group_layouts = [_]c.WGPUBindGroupId{bind_group_layout};

        ////////////////////////////////////////////////////////////////////////////
        // Render pipelines
        const pipeline_layout = c.wgpu_device_create_pipeline_layout(
            device,
            &(c.WGPUPipelineLayoutDescriptor){
                .bind_group_layouts = &bind_group_layouts,
                .bind_group_layouts_length = bind_group_layouts.len,
            },
        );
        defer c.wgpu_pipeline_layout_destroy(pipeline_layout);

        const render_pipeline = c.wgpu_device_create_render_pipeline(
            device,
            &(c.WGPURenderPipelineDescriptor){
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
                    .depth_bias = 0,
                    .depth_bias_slope_scale = 0.0,
                    .depth_bias_clamp = 0.0,
                },
                .primitive_topology = c.WGPUPrimitiveTopology._TriangleList,
                .color_states = &(c.WGPUColorStateDescriptor){
                    .format = c.WGPUTextureFormat._Bgra8Unorm,
                    .alpha_blend = (c.WGPUBlendDescriptor){
                        .src_factor = c.WGPUBlendFactor._One,
                        .dst_factor = c.WGPUBlendFactor._Zero,
                        .operation = c.WGPUBlendOperation._Add,
                    },
                    .color_blend = (c.WGPUBlendDescriptor){
                        .src_factor = c.WGPUBlendFactor._One,
                        .dst_factor = c.WGPUBlendFactor._Zero,
                        .operation = c.WGPUBlendOperation._Add,
                    },
                    .write_mask = c.WGPUColorWrite_ALL,
                },
                .color_states_length = 1,
                .depth_stencil_state = null,
                .vertex_state = (c.WGPUVertexStateDescriptor){
                    .index_format = c.WGPUIndexFormat._Uint16,
                    .vertex_buffers = null,
                    .vertex_buffers_length = 0,
                },
                .sample_count = 1,
                .sample_mask = 0,
                .alpha_to_coverage_enabled = false,
            },
        );

        var out = Self{
            .device = device,
            .queue = c.wgpu_device_get_default_queue(device),
            .tex_sampler = tex_sampler,
            .render_pipeline = render_pipeline,
            .bind_group_layout = bind_group_layout,
            .bind_group = undefined, // Assigned in bind_to_tex below
        };
        out.bind_(tex_view, uniform_buf, false);
        return out;
    }

    // Unchecked bind_to_tex variation, for use in constructor
    fn bind_(
        self: *Self,
        tex_view: c.WGPUTextureViewId,
        uniform_buf: c.WGPUBufferId,
        del_prev: bool,
    ) void {
        if (del_prev) {
            c.wgpu_bind_group_destroy(self.bind_group);
        }
        const bind_group_entries = [_]c.WGPUBindGroupEntry{
            (c.WGPUBindGroupEntry){
                .binding = 0,
                .texture_view = tex_view,
                .sampler = 0, // None
                .buffer = 0, // None

                .offset = undefined,
                .size = undefined,
            },
            (c.WGPUBindGroupEntry){
                .binding = 1,
                .sampler = self.tex_sampler,
                .texture_view = 0, // None
                .buffer = 0, // None

                .offset = undefined,
                .size = undefined,
            },
            (c.WGPUBindGroupEntry){
                .binding = 2,
                .buffer = uniform_buf,
                .offset = 0,
                .size = @sizeOf(c.rayUniforms),

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

    pub fn bind(
        self: *Self,
        tex_view: c.WGPUTextureViewId,
        uniform_buf: c.WGPUBufferId,
    ) void {
        self.bind_(tex_view, uniform_buf, true);
    }

    pub fn deinit(self: *Self) void {
        c.wgpu_sampler_destroy(self.tex_sampler);
        c.wgpu_bind_group_layout_destroy(self.bind_group_layout);
        c.wgpu_bind_group_destroy(self.bind_group);
    }

    pub fn draw(
        self: *const Self,
        next_texture: c.WGPUSwapChainOutput,
        cmd_encoder: c.WGPUCommandEncoderId,
    ) void {
        const color_attachments = [_]c.WGPURenderPassColorAttachmentDescriptor{
            (c.WGPURenderPassColorAttachmentDescriptor){
                .attachment = next_texture.view_id,
                .resolve_target = 0,
                .channel = (c.WGPUPassChannel_Color){
                    .load_op = c.WGPULoadOp._Load,
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
