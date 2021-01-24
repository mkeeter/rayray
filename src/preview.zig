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

    uniform_buf: c.WGPUBufferId, // owned by the parent Renderer
    scene_buf: c.WGPUBufferId,
    scene_buf_len: usize,

    image_buf: c.WGPUBufferId, // owned by the parent Renderer
    image_buf_size: u32,

    compute_pipeline: c.WGPUComputePipelineId,

    pub fn init(
        alloc: *std.mem.Allocator,
        scene: Scene,
        device: c.WGPUDeviceId,
        uniform_buf: c.WGPUBufferId,
        image_buf: c.WGPUBufferId,
        image_buf_size: u32,
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
            .scene_buf = undefined, // assigned in upload_scene() below
            .scene_buf_len = 0,
            .uniform_buf = uniform_buf,

            .image_buf = image_buf,
            .image_buf_size = image_buf_size,

            .compute_pipeline = compute_pipeline,
        };
        try out.upload_scene(scene);
        out.initialized = true;
        return out;
    }

    pub fn bind(self: *Self, image_buf: c.WGPUBufferId, image_buf_size: u32) void {
        self.image_buf = image_buf;
        self.image_buf_size = image_buf_size;
        self.rebuild_bind_group();
    }

    pub fn deinit(self: *Self) void {
        c.wgpu_bind_group_destroy(self.bind_group);
        c.wgpu_bind_group_layout_destroy(self.bind_group_layout);
        c.wgpu_buffer_destroy(self.scene_buf, true);

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
                .buffer = self.uniform_buf,
                .offset = 0,
                .size = @sizeOf(c.rayUniforms),

                .sampler = 0, // None
                .texture_view = 0, // None
            },
            (c.WGPUBindGroupEntry){
                .binding = 1,
                .buffer = self.image_buf,
                .offset = 0,
                .size = self.image_buf_size,

                .sampler = 0, // None
                .texture_view = 0, // None
            },
            (c.WGPUBindGroupEntry){
                .binding = 2,
                .buffer = self.scene_buf,
                .offset = 0,
                .size = self.scene_buf_len,

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

        const scene_buf_len = encoded.len * @sizeOf(c.vec4);

        if (scene_buf_len > self.scene_buf_len) {
            if (self.initialized) {
                c.wgpu_buffer_destroy(self.scene_buf, true);
            }
            self.scene_buf = c.wgpu_device_create_buffer(
                self.device,
                &(c.WGPUBufferDescriptor){
                    .label = "raytrace scene",
                    .size = scene_buf_len,
                    .usage = c.WGPUBufferUsage_STORAGE | c.WGPUBufferUsage_COPY_DST,
                    .mapped_at_creation = false,
                },
            );
            self.scene_buf_len = scene_buf_len;
            self.rebuild_bind_group();
        }

        c.wgpu_queue_write_buffer(
            self.queue,
            self.scene_buf,
            0,
            @ptrCast([*c]const u8, encoded.ptr),
            encoded.len * @sizeOf(c.vec4),
        );
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
