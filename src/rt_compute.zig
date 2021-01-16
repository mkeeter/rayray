const std = @import("std");

const c = @import("c.zig");
const shaderc = @import("shaderc.zig");
const Options = @import("options.zig").Options;

const Scene = @import("scene.zig").Scene;

pub const RaytraceCompute = struct {
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

    compute_pipeline: c.WGPUComputePipelineId,

    scene: Scene,

    pub fn init(
        alloc: *std.mem.Allocator,
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
        const comp_spv = try shaderc.build_shader_from_file(tmp_alloc, "shaders/raytrace.comp");
        const comp_shader = c.wgpu_device_create_shader_module(
            device,
            (c.WGPUShaderSource){
                .bytes = comp_spv.ptr,
                .length = comp_spv.len,
            },
        );
        defer c.wgpu_shader_module_destroy(comp_shader);

        ////////////////////////////////////////////////////////////////////////
        // Make a dummy scene buffer; we'll later resize to fit the scene
        const scene_buffer_len = 4;
        const scene_buffer = c.wgpu_device_create_buffer(
            device,
            &(c.WGPUBufferDescriptor){
                .label = "raytrace scene",
                .size = scene_buffer_len,
                .usage = c.WGPUBufferUsage_STORAGE | c.WGPUBufferUsage_COPY_DST,
                .mapped_at_creation = false,
            },
        );

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
                .view_dimension = undefined,
                .texture_component_type = undefined,
                .storage_texture_format = undefined,
                .count = undefined,
            },
            (c.WGPUBindGroupLayoutEntry){ // Scene buffer
                .binding = 1,
                .visibility = c.WGPUShaderStage_COMPUTE,
                .ty = c.WGPUBindingType_ReadonlyStorageBuffer,

                .has_dynamic_offset = false,
                .min_buffer_binding_size = 0,

                .multisampled = undefined,
                .view_dimension = undefined,
                .texture_component_type = undefined,
                .storage_texture_format = undefined,
                .count = undefined,
            },
            (c.WGPUBindGroupLayoutEntry){ // Output image
                .binding = 2,
                .visibility = c.WGPUShaderStage_COMPUTE,
                .ty = c.WGPUBindingType_WriteonlyStorageTexture,

                .storage_texture_format = c.WGPUTextureFormat._Rgba32Float,
                .view_dimension = c.WGPUTextureViewDimension._D2,

                .has_dynamic_offset = undefined,
                .min_buffer_binding_size = undefined,

                .multisampled = undefined,
                .texture_component_type = undefined,
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

        const compute_pipeline = c.wgpu_device_create_compute_pipeline(
            device,
            &(c.WGPUComputePipelineDescriptor){
                .layout = pipeline_layout,
                .compute_stage = (c.WGPUProgrammableStageDescriptor){
                    .module = comp_shader,
                    .entry_point = "main",
                },
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
            .scene_buffer_len = scene_buffer_len,
            .uniform_buffer = uniform_buf,

            .tex = undefined, // assigned in resize() below
            .tex_view = undefined, // assigned in resize() below

            .compute_pipeline = compute_pipeline,
            .scene = try Scene.new_simple_scene(alloc),
        };
        out.resize_(options.width, options.height, false);
        try out.upload_scene_(false);
        return out;
    }

    fn destroy_textures(self: *Self) void {
        c.wgpu_texture_destroy(self.tex);
        c.wgpu_texture_view_destroy(self.tex_view);
    }

    pub fn deinit(self: *Self) void {
        self.destroy_textures();
        self.scene.deinit();

        c.wgpu_bind_group_destroy(self.bind_group);
        c.wgpu_bind_group_layout_destroy(self.bind_group_layout);
        c.wgpu_buffer_destroy(self.scene_buffer);

        c.wgpu_compute_pipeline_destroy(self.compute_pipeline);
    }

    fn resize_(self: *Self, width: u32, height: u32, del_prev_tex: bool) void {
        std.debug.print("Resizing compute shader to {} x {}\n", .{ width, height });
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

                // We render to this texture in a compute shader, then use it
                // as a source when blitting into the final UI image
                .usage = c.WGPUTextureUsage_STORAGE |
                    c.WGPUTextureUsage_SAMPLED,
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
        // If this isn't our first run, then regenerate the bind group
        // (we can't do that on the first run because the scene buffer doesn't
        // exist yet)
        if (del_prev_tex) {
            self.rebuild_bind_group(del_prev_tex);
        }
    }

    fn rebuild_bind_group(self: *Self, del_prev: bool) void {
        if (del_prev) {
            c.wgpu_bind_group_destroy(self.bind_group);
        }

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
            (c.WGPUBindGroupEntry){
                .binding = 2,
                .texture_view = self.tex_view,
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

    pub fn resize(self: *Self, width: u32, height: u32) void {
        self.resize_(width, height, true);
    }

    // Copies the scene from self.scene to the GPU, rebuilding the bind
    // group if the buffer has been resized (which would invalidate it)
    fn upload_scene_(self: *Self, del_prev: bool) !void {
        const encoded = try self.scene.encode();
        defer self.alloc.free(encoded);

        const scene_buffer_len = encoded.len * @sizeOf(c.vec4);

        if (scene_buffer_len > self.scene_buffer_len) {
            if (del_prev) {
                c.wgpu_buffer_destroy(self.scene_buffer);
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
            self.rebuild_bind_group(del_prev);
        }

        c.wgpu_queue_write_buffer(
            self.queue,
            self.scene_buffer,
            0,
            @ptrCast([*c]const u8, encoded.ptr),
            encoded.len * @sizeOf(c.vec4),
        );
    }

    fn upload_scene(self: *Self) !void {
        try self.upload_scene_(true);
    }

    pub fn draw(self: *Self, first: bool, cmd_encoder: c.WGPUCommandEncoderId) !void {
        if (first) {
            std.debug.print("Uploading scene\n", .{});
            try self.upload_scene();
        }

        const cpass = c.wgpu_command_encoder_begin_compute_pass(
            cmd_encoder,
            &(c.WGPUComputePassDescriptor){ .todo = 1 }, // :|
        );

        c.wgpu_compute_pass_set_pipeline(cpass, self.compute_pipeline);
        c.wgpu_compute_pass_set_bind_group(cpass, 0, self.bind_group, null, 0);
        c.wgpu_compute_pass_dispatch(cpass, 1200, 1200, 1);
        c.wgpu_compute_pass_end_pass(cpass);
    }
};
