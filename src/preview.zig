const std = @import("std");

const c = @import("c.zig");
const shaderc = @import("shaderc.zig");

const Scene = @import("scene.zig").Scene;

// This struct runs a raytracing kernel which uses an encoded scene and
// tape to evaluate generic scenes.  This is slower than compiling a
// scene-specific kernel, but is much more efficient to update (because
// you only need to modify the scene storage buffer).
pub const Preview = struct {
    const Self = @This();

    alloc: *std.mem.Allocator,
    initialized: bool = false,

    // GPU handles
    device: c.WGPUDeviceId,
    queue: c.WGPUQueueId,

    bind_group: c.WGPUBindGroupId,
    bind_group_layout: c.WGPUBindGroupLayoutId,

    uniform_buffer: c.WGPUBufferId, // owned by the parent Renderer
    scene_buffer: c.WGPUBufferId,
    scene_buffer_len: usize,

    tex_view: c.WGPUTextureViewId, // owned by the parent Renderer

    compute_pipeline: c.WGPUComputePipelineId,

    pub fn init(
        alloc: *std.mem.Allocator,
        scene: Scene,
        device: c.WGPUDeviceId,
        uniform_buf: c.WGPUBufferId,
        tex_view: c.WGPUTextureViewId,
    ) !Self {
        var arena = std.heap.ArenaAllocator.init(alloc);
        const tmp_alloc: *std.mem.Allocator = &arena.allocator;
        defer arena.deinit();

        // This is the only available queue right now
        const queue = c.wgpu_device_get_default_queue(device);

        // Build the shaders using shaderc
        const comp_name = "shaders/preview.comp";
        const comp_spv = try shaderc.build_shader_from_file(tmp_alloc, comp_name);
        const comp_shader = c.wgpu_device_create_shader_module(
            device,
            &(c.WGPUShaderModuleDescriptor){
                .label = comp_name,
                .bytes = comp_spv.ptr,
                .length = comp_spv.len,
                .flags = c.WGPUShaderFlags_VALIDATION,
            },
        );
        defer c.wgpu_shader_module_destroy(comp_shader);

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
            (c.WGPUBindGroupLayoutEntry){ // Scene buffer
                .binding = 2,
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
        const bind_group_layouts = [_]c.WGPUBindGroupId{bind_group_layout};

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
            .alloc = alloc,

            .device = device,
            .queue = queue,

            .bind_group = undefined, // assigned in upload_scene() below
            .bind_group_layout = bind_group_layout,
            .scene_buffer = undefined, // assigned in upload_scene() below
            .scene_buffer_len = 0,
            .uniform_buffer = uniform_buf,

            .tex_view = tex_view,

            .compute_pipeline = compute_pipeline,
        };
        try out.upload_scene(scene);
        out.initialized = true;
        return out;
    }

    pub fn bind(self: *Self, tex_view: c.WGPUTextureViewId) void {
        self.tex_view = tex_view;
        self.rebuild_bind_group();
    }

    pub fn deinit(self: *Self) void {
        c.wgpu_bind_group_destroy(self.bind_group);
        c.wgpu_bind_group_layout_destroy(self.bind_group_layout);
        c.wgpu_buffer_destroy(self.scene_buffer, true);

        c.wgpu_compute_pipeline_destroy(self.compute_pipeline);
    }

    fn rebuild_bind_group(self: *Self) void {
        if (self.initialized) {
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
                .texture_view = self.tex_view,
                .buffer = 0, // None
                .sampler = 0, // None

                .offset = undefined,
                .size = undefined,
            },
            (c.WGPUBindGroupEntry){
                .binding = 2,
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

    // Copies the scene from self.scene to the GPU, rebuilding the bind
    // group if the buffer has been resized (which would invalidate it)
    pub fn upload_scene(self: *Self, scene: Scene) !void {
        const encoded = try scene.encode();
        defer self.alloc.free(encoded);

        const scene_buffer_len = encoded.len * @sizeOf(c.vec4);

        if (scene_buffer_len > self.scene_buffer_len) {
            if (self.initialized) {
                c.wgpu_buffer_destroy(self.scene_buffer, true);
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
            self.rebuild_bind_group();
        }

        c.wgpu_queue_write_buffer(
            self.queue,
            self.scene_buffer,
            0,
            @ptrCast([*c]const u8, encoded.ptr),
            encoded.len * @sizeOf(c.vec4),
        );
    }

    pub fn render(
        self: *Self,
        first: bool,
        width: u32,
        height: u32,
        cmd_encoder: c.WGPUCommandEncoderId,
    ) !void {
        const cpass = c.wgpu_command_encoder_begin_compute_pass(
            cmd_encoder,
            &(c.WGPUComputePassDescriptor){ .label = "" },
        );

        c.wgpu_compute_pass_set_pipeline(cpass, self.compute_pipeline);
        c.wgpu_compute_pass_set_bind_group(cpass, 0, self.bind_group, null, 0);
        c.wgpu_compute_pass_dispatch(cpass, width / 16, height / 4, 1);
        c.wgpu_compute_pass_end_pass(cpass);
    }
};
