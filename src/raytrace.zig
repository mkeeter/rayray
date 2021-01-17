const std = @import("std");

const c = @import("c.zig");
const shaderc = @import("shaderc.zig");
const Options = @import("options.zig").Options;

const Scene = @import("scene.zig").Scene;

pub const Raytrace = struct {
    const Self = @This();

    alloc: *std.mem.Allocator,

    // GPU handles
    device: c.WGPUDeviceId,
    queue: c.WGPUQueueId,

    // We accumulate rays into this texture, then blit it to the screen
    tex: c.WGPUTextureId,
    tex_view: c.WGPUTextureViewId,

    bind_group: c.WGPUBindGroupId,
    bind_group_layout: c.WGPUBindGroupLayoutId,

    uniform_buffer: c.WGPUBufferId, // owned by the parent Renderer
    scene_buffer: c.WGPUBufferId,
    scene_buffer_len: usize,

    render_pipeline: c.WGPURenderPipelineId,

    pub fn init(
        alloc: *std.mem.Allocator,
        scene: Scene,
        device: c.WGPUDeviceId,
        options: Options,
        uniform_buf: c.WGPUBufferId,
    ) !Self {
        var arena = std.heap.ArenaAllocator.init(alloc);
        const tmp_alloc: *std.mem.Allocator = &arena.allocator;
        defer arena.deinit();

        // This is the only available queue right now
        const queue = c.wgpu_device_get_default_queue(device);

        // Build the shaders using shaderc
        const vert_spv = try shaderc.build_shader_from_file(tmp_alloc, "shaders/raytrace.vert");
        const vert_shader = c.wgpu_device_create_shader_module(
            device,
            (c.WGPUShaderSource){
                .bytes = vert_spv.ptr,
                .length = vert_spv.len,
            },
        );
        defer c.wgpu_shader_module_destroy(vert_shader);
        const frag_spv = try shaderc.build_shader_from_file(tmp_alloc, "shaders/raytrace.frag");
        const frag_shader = c.wgpu_device_create_shader_module(
            device,
            (c.WGPUShaderSource){
                .bytes = frag_spv.ptr,
                .length = frag_spv.len,
            },
        );
        defer c.wgpu_shader_module_destroy(frag_shader);

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
                .view_dimension = undefined,
                .texture_component_type = undefined,
                .storage_texture_format = undefined,
                .count = undefined,
            },
            (c.WGPUBindGroupLayoutEntry){ // Scene buffer
                .binding = 1,
                .visibility = c.WGPUShaderStage_FRAGMENT,
                .ty = c.WGPUBindingType_StorageBuffer,

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

        ////////////////////////////////////////////////////////////////////////
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
                    .index_format = c.WGPUIndexFormat._Uint16,
                    .vertex_buffers = null,
                    .vertex_buffers_length = 0,
                },
                .sample_count = 1,
                .sample_mask = 0,
                .alpha_to_coverage_enabled = false,
            },
        );

        ////////////////////////////////////////////////////////////////////////
        var out = Self{
            .alloc = alloc,

            .device = device,
            .queue = queue,

            .bind_group = undefined, // assigned in upload_scene() below
            .bind_group_layout = bind_group_layout,
            .scene_buffer = undefined, // assigned in upload_scene() below
            .scene_buffer_len = 0,
            .uniform_buffer = uniform_buf,

            .tex = undefined, // assigned in resize() below
            .tex_view = undefined, // assigned in resize() below

            .render_pipeline = render_pipeline,
        };
        out.resize_(options.width, options.height, false);
        try out.upload_scene_(scene, false);
        return out;
    }

    fn destroy_textures(self: *Self) void {
        c.wgpu_texture_destroy(self.tex);
        c.wgpu_texture_view_destroy(self.tex_view);
    }

    pub fn deinit(self: *Self) void {
        self.destroy_textures();

        c.wgpu_bind_group_destroy(self.bind_group);
        c.wgpu_bind_group_layout_destroy(self.bind_group_layout);
        c.wgpu_buffer_destroy(self.scene_buffer);

        c.wgpu_render_pipeline_destroy(self.render_pipeline);
    }

    fn resize_(self: *Self, width: u32, height: u32, del_prev_tex: bool) void {
        if (del_prev_tex) {
            self.destroy_textures();
        }
        self.tex = c.wgpu_device_create_texture(
            self.device,
            &(c.WGPUTextureDescriptor){
                .size = .{
                    .width = width,
                    .height = height,
                    .depth = 1,
                },
                .mip_level_count = 1,
                .sample_count = 1,
                .dimension = c.WGPUTextureDimension._D2,
                .format = c.WGPUTextureFormat._Rgba32Float,

                // We render to this texture, then use it as a source when
                // blitting into the final UI image
                .usage = (c.WGPUTextureUsage_OUTPUT_ATTACHMENT |
                    c.WGPUTextureUsage_SAMPLED),
                .label = "raytrace_tex",
            },
        );
        self.tex_view = c.wgpu_texture_create_view(
            self.tex,
            &(c.WGPUTextureViewDescriptor){
                .label = "raytrace_tex_view",
                .dimension = c.WGPUTextureViewDimension._D2,
                .format = c.WGPUTextureFormat._Rgba32Float,
                .aspect = c.WGPUTextureAspect._All,
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .array_layer_count = 1,
            },
        );
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        self.resize_(width, height, true);
    }

    // Copies the scene from self.scene to the GPU, rebuilding the bind
    // group if the buffer has been resized (which would invalidate it)
    fn upload_scene_(self: *Self, scene: Scene, del_prev: bool) !void {
        const encoded = try scene.encode();
        defer self.alloc.free(encoded);

        const scene_buffer_len = encoded.len * @sizeOf(c.vec4);

        if (scene_buffer_len > self.scene_buffer_len) {
            if (del_prev) {
                c.wgpu_buffer_destroy(self.scene_buffer);
                c.wgpu_bind_group_destroy(self.bind_group);
            }
            self.scene_buffer = c.wgpu_device_create_buffer(
                self.device,
                &(c.WGPUBufferDescriptor){
                    .label = "raytrace scene",
                    .size = scene_buffer_len,
                    .usage = c.WGPUBufferUsage_STORAGE | c.WGPUBufferUsage_COPY_DST,
                    .mapped_at_creation = false,
                },
            );
            self.scene_buffer_len = scene_buffer_len;

            // Rebuild the bind group as well
            const bind_group_entries = [_]c.WGPUBindGroupEntry{
                (c.WGPUBindGroupEntry){
                    .binding = 0,
                    .buffer = self.uniform_buffer,
                    .offset = 0,
                    .size = @sizeOf(c.rayUniforms),

                    .sampler = 0, // None
                    .texture_view = 0, // None
                },
                (c.WGPUBindGroupEntry){
                    .binding = 1,
                    .buffer = self.scene_buffer,
                    .offset = 0,
                    .size = self.scene_buffer_len,

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

        c.wgpu_queue_write_buffer(
            self.queue,
            self.scene_buffer,
            0,
            @ptrCast([*c]const u8, encoded.ptr),
            encoded.len * @sizeOf(c.vec4),
        );
    }

    pub fn upload_scene(self: *Self, scene: Scene) !void {
        try self.upload_scene_(scene, true);
    }

    pub fn draw(self: *Self, first: bool, cmd_encoder: c.WGPUCommandEncoderId) !void {
        const load_op = if (first)
            c.WGPULoadOp._Clear
        else
            c.WGPULoadOp._Load;
        const color_attachments = [_]c.WGPURenderPassColorAttachmentDescriptor{
            (c.WGPURenderPassColorAttachmentDescriptor){
                .attachment = self.tex_view,
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
