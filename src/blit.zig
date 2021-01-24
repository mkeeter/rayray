const std = @import("std");

const c = @import("c.zig");
const shaderc = @import("shaderc.zig");

const Viewport = @import("viewport.zig").Viewport;

pub const Blit = struct {
    const Self = @This();

    initialized: bool = false,

    device: c.WGPUDeviceId,
    queue: c.WGPUQueueId,

    bind_group_layout: c.WGPUBindGroupLayoutId,
    bind_group: c.WGPUBindGroupId,

    render_pipeline: c.WGPURenderPipelineId,

    pub fn init(
        alloc: *std.mem.Allocator,
        device: c.WGPUDeviceId,
        uniform_buf: c.WGPUBufferId,
        image_buf: c.WGPUBufferId,
        image_buf_size: u32,
    ) !Blit {
        var arena = std.heap.ArenaAllocator.init(alloc);
        const tmp_alloc: *std.mem.Allocator = &arena.allocator;
        defer arena.deinit();

        ////////////////////////////////////////////////////////////////////////////
        // Build the shaders using shaderc
        const blit_vert_name = "shaders/blit.vert";
        const vert_spv = shaderc.build_shader_from_file(tmp_alloc, blit_vert_name) catch |err| {
            std.debug.panic("Could not open file", .{});
        };
        const vert_shader = c.wgpu_device_create_shader_module(
            device,
            &(c.WGPUShaderModuleDescriptor){
                .label = blit_vert_name,
                .bytes = vert_spv.ptr,
                .length = vert_spv.len,
                .flags = c.WGPUShaderFlags_VALIDATION,
            },
        );
        defer c.wgpu_shader_module_destroy(vert_shader);

        const blit_frag_name = "shaders/blit.frag";
        const frag_spv = shaderc.build_shader_from_file(tmp_alloc, blit_frag_name) catch |err| {
            std.debug.panic("Could not open file", .{});
        };
        const frag_shader = c.wgpu_device_create_shader_module(
            device,
            &(c.WGPUShaderModuleDescriptor){
                .label = blit_frag_name,
                .bytes = frag_spv.ptr,
                .length = frag_spv.len,
                .flags = c.WGPUShaderFlags_VALIDATION,
            },
        );
        defer c.wgpu_shader_module_destroy(frag_shader);

        ////////////////////////////////////////////////////////////////////////////
        // Bind groups
        const bind_group_layout_entries = [_]c.WGPUBindGroupLayoutEntry{
            (c.WGPUBindGroupLayoutEntry){ // Pseudo-texture
                .binding = 0,
                .visibility = c.WGPUShaderStage_FRAGMENT,
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
            (c.WGPUBindGroupLayoutEntry){ // Uniforms buffer
                .binding = 1,
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
        const bind_group_layouts = [_]c.WGPUBindGroupId{bind_group_layout};

        ////////////////////////////////////////////////////////////////////////////
        // Render pipelines
        const pipeline_layout = c.wgpu_device_create_pipeline_layout(
            device,
            &(c.WGPUPipelineLayoutDescriptor){
                .label = "blit pipeline",
                .bind_group_layouts = &bind_group_layouts,
                .bind_group_layouts_length = bind_group_layouts.len,
            },
        );
        defer c.wgpu_pipeline_layout_destroy(pipeline_layout);

        const render_pipeline = c.wgpu_device_create_render_pipeline(
            device,
            &(c.WGPURenderPipelineDescriptor){
                .label = "blit render pipeline",
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
                    .polygon_mode = c.WGPUPolygonMode._Fill,
                    .clamp_depth = false,
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
                    .index_format = c.WGPUIndexFormat_Undefined,
                    .vertex_buffers = null,
                    .vertex_buffers_length = 0,
                },
                .sample_count = 1,
                .sample_mask = 0,
                .alpha_to_coverage = false,
            },
        );

        var out = Self{
            .device = device,
            .queue = c.wgpu_device_get_default_queue(device),
            .render_pipeline = render_pipeline,
            .bind_group_layout = bind_group_layout,
            .bind_group = undefined, // Assigned in bind below
        };
        out.bind(uniform_buf, image_buf, image_buf_size);
        out.initialized = true;
        return out;
    }

    pub fn bind(
        self: *Self,
        uniform_buf: c.WGPUBufferId,
        image_buf: c.WGPUBufferId,
        image_buf_size: u32,
    ) void {
        if (self.initialized) {
            c.wgpu_bind_group_destroy(self.bind_group);
        }
        const bind_group_entries = [_]c.WGPUBindGroupEntry{
            (c.WGPUBindGroupEntry){
                .binding = 0,
                .buffer = image_buf,
                .offset = 0,
                .size = image_buf_size,

                .sampler = 0, // None
                .texture_view = 0, // None
            },
            (c.WGPUBindGroupEntry){
                .binding = 1,
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

    pub fn deinit(self: *Self) void {
        c.wgpu_bind_group_layout_destroy(self.bind_group_layout);
        c.wgpu_bind_group_destroy(self.bind_group);
    }

    pub fn draw(
        self: *const Self,
        viewport: Viewport,
        next_texture: c.WGPUOption_TextureViewId,
        cmd_encoder: c.WGPUCommandEncoderId,
    ) void {
        const color_attachments = [_]c.WGPUColorAttachmentDescriptor{
            (c.WGPUColorAttachmentDescriptor){
                .attachment = next_texture,
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
                .label = "blit rpass",
                .color_attachments = &color_attachments,
                .color_attachments_length = color_attachments.len,
                .depth_stencil_attachment = null,
            },
        );

        c.wgpu_render_pass_set_pipeline(rpass, self.render_pipeline);
        c.wgpu_render_pass_set_bind_group(rpass, 0, self.bind_group, null, 0);
        c.wgpu_render_pass_set_viewport(
            rpass,
            viewport.x,
            viewport.y,
            viewport.width,
            viewport.height,
            0,
            1,
        );
        c.wgpu_render_pass_draw(rpass, 3, 1, 0, 0);
        c.wgpu_render_pass_end_pass(rpass);
    }
};
