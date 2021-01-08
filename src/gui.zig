// Dear Imgui backend for GLFW and WebGPU
//
// The GLFW logic is roughly based on imgui_impl_glfw.cpp;
// the WebGPU implementation is custom but inspired by imgui_impl_opengl3.cpp
const std = @import("std");

const c = @import("c.zig");
const shaderc = @import("shaderc.zig");

pub const Gui = struct {
    const Self = @This();

    ctx: *c.ImGuiContext,
    time_ms: ?i64,

    device: c.WGPUDeviceId,
    queue: c.WGPUQueueId,

    uniform_buf: c.WGPUBufferId,
    bind_group_layout: c.WGPUBindGroupLayoutId,

    // The font texture lives in io.TexID, but we save it here so that we
    // can destroy it when the Gui is deleted
    font_tex: c.WGPUTextureId,
    font_tex_view: c.WGPUTextureViewId,

    tex_sampler: c.WGPUSamplerId, // Used for any texture

    // These buffers are dynamically resized as needed.
    //
    // This requires recreating the bind group, so we don't shrink them
    // if the GUI buffer size becomes smaller.
    vertex_buf: c.WGPUBufferId,
    vertex_buf_size: usize,
    index_buf: c.WGPUBufferId,
    index_buf_size: usize,

    render_pipeline: c.WGPURenderPipelineId,

    pub fn init(alloc: *std.mem.Allocator, device: c.WGPUDeviceId) !Self {
        const ctx = c.igCreateContext(null);
        c.igSetCurrentContext(ctx);

        // Setup backend capabilities flags
        var io = c.igGetIO() orelse std.debug.panic("Could not get io\n", .{});
        io.*.BackendPlatformName = "imgui_impl_glfw_zig";

        // Keyboard mapping. ImGui will use those indices to peek into the io.KeysDown[] array.
        io.*.KeyMap[c.ImGuiKey_Tab] = c.GLFW_KEY_TAB;
        io.*.KeyMap[c.ImGuiKey_LeftArrow] = c.GLFW_KEY_LEFT;
        io.*.KeyMap[c.ImGuiKey_RightArrow] = c.GLFW_KEY_RIGHT;
        io.*.KeyMap[c.ImGuiKey_UpArrow] = c.GLFW_KEY_UP;
        io.*.KeyMap[c.ImGuiKey_DownArrow] = c.GLFW_KEY_DOWN;
        io.*.KeyMap[c.ImGuiKey_PageUp] = c.GLFW_KEY_PAGE_UP;
        io.*.KeyMap[c.ImGuiKey_PageDown] = c.GLFW_KEY_PAGE_DOWN;
        io.*.KeyMap[c.ImGuiKey_Home] = c.GLFW_KEY_HOME;
        io.*.KeyMap[c.ImGuiKey_End] = c.GLFW_KEY_END;
        io.*.KeyMap[c.ImGuiKey_Insert] = c.GLFW_KEY_INSERT;
        io.*.KeyMap[c.ImGuiKey_Delete] = c.GLFW_KEY_DELETE;
        io.*.KeyMap[c.ImGuiKey_Backspace] = c.GLFW_KEY_BACKSPACE;
        io.*.KeyMap[c.ImGuiKey_Space] = c.GLFW_KEY_SPACE;
        io.*.KeyMap[c.ImGuiKey_Enter] = c.GLFW_KEY_ENTER;
        io.*.KeyMap[c.ImGuiKey_Escape] = c.GLFW_KEY_ESCAPE;
        io.*.KeyMap[c.ImGuiKey_KeyPadEnter] = c.GLFW_KEY_KP_ENTER;
        io.*.KeyMap[c.ImGuiKey_A] = c.GLFW_KEY_A;
        io.*.KeyMap[c.ImGuiKey_C] = c.GLFW_KEY_C;
        io.*.KeyMap[c.ImGuiKey_V] = c.GLFW_KEY_V;
        io.*.KeyMap[c.ImGuiKey_X] = c.GLFW_KEY_X;
        io.*.KeyMap[c.ImGuiKey_Y] = c.GLFW_KEY_Y;
        io.*.KeyMap[c.ImGuiKey_Z] = c.GLFW_KEY_Z;

        ////////////////////////////////////////////////////////////////////////
        // TIME FOR WGPU
        var arena = std.heap.ArenaAllocator.init(alloc);
        const tmp_alloc: *std.mem.Allocator = &arena.allocator;
        defer arena.deinit();

        // This is the only available queue right now
        const queue = c.wgpu_device_get_default_queue(device);

        // Build the shaders using shaderc
        const vert_spv = try shaderc.build_shader_from_file(tmp_alloc, "shaders/gui.vert");
        const vert_shader = c.wgpu_device_create_shader_module(
            device,
            (c.WGPUShaderSource){
                .bytes = vert_spv.ptr,
                .length = vert_spv.len,
            },
        );
        defer c.wgpu_shader_module_destroy(vert_shader);
        const frag_spv = try shaderc.build_shader_from_file(tmp_alloc, "shaders/gui.frag");
        const frag_shader = c.wgpu_device_create_shader_module(
            device,
            (c.WGPUShaderSource){
                .bytes = frag_spv.ptr,
                .length = frag_spv.len,
            },
        );
        defer c.wgpu_shader_module_destroy(frag_shader);

        ////////////////////////////////////////////////////////////////////////
        // Uniform buffers
        const uniform_buf = c.wgpu_device_create_buffer(
            device,
            &(c.WGPUBufferDescriptor){
                .label = "gui uniforms",
                .size = @sizeOf(f32) * 4 * 4, // mat4
                .usage = c.WGPUBufferUsage_UNIFORM | c.WGPUBufferUsage_COPY_DST,
                .mapped_at_creation = false,
            },
        );

        ///////////////////////////////////////////////////////////////////////
        // Font texture
        var font_pixels: ?*u8 = undefined;
        var font_width: c_int = undefined;
        var font_height: c_int = undefined;
        var bytes_per_pixel: c_int = undefined;
        c.ImFontAtlas_GetTexDataAsRGBA32(
            io.*.Fonts,
            &font_pixels,
            &font_width,
            &font_height,
            &bytes_per_pixel,
        );
        const font_tex = c.wgpu_device_create_texture(
            device,
            &(c.WGPUTextureDescriptor){
                .size = .{
                    .width = @intCast(u32, font_width),
                    .height = @intCast(u32, font_height),
                    .depth = 1,
                },
                .mip_level_count = 1,
                .sample_count = 1,
                .dimension = c.WGPUTextureDimension._D2,
                .format = c.WGPUTextureFormat._Rgba8Unorm,

                .usage = (c.WGPUTextureUsage_COPY_DST |
                    c.WGPUTextureUsage_SAMPLED),
                .label = "gui font tex",
            },
        );
        const font_tex_view = c.wgpu_texture_create_view(
            font_tex,
            &(c.WGPUTextureViewDescriptor){
                .label = "font font view",
                .dimension = c.WGPUTextureViewDimension._D2,
                .format = c.WGPUTextureFormat._Rgba8Unorm,
                .aspect = c.WGPUTextureAspect._All,
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .array_layer_count = 1,
            },
        );
        const font_tex_size = (c.WGPUExtent3d){
            .width = @intCast(u32, font_width),
            .height = @intCast(u32, font_height),
            .depth = 1,
        };
        c.wgpu_queue_write_texture(
            queue,
            &(c.WGPUTextureCopyView){
                .texture = font_tex,
                .mip_level = 0,
                .origin = (c.WGPUOrigin3d){ .x = 0, .y = 0, .z = 0 },
            },
            @ptrCast([*]const u8, font_pixels),
            @intCast(usize, font_width) * @intCast(usize, font_height) * @sizeOf(u32),
            &(c.WGPUTextureDataLayout){
                .offset = 0,
                .bytes_per_row = @intCast(u32, font_width) * @sizeOf(u32),
                .rows_per_image = @intCast(u32, font_height) * @sizeOf(u32),
            },
            &font_tex_size,
        );
        io.*.Fonts.*.TexID = @intToPtr(*c_void, font_tex_view);

        ///////////////////////////////////////////////////////////////////////
        // Texture sampler (the font texture is handled above)
        const tex_sampler = c.wgpu_device_create_sampler(device, &(c.WGPUSamplerDescriptor){
            .next_in_chain = null,
            .label = "gui tex sampler",
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
            (c.WGPUBindGroupLayoutEntry){ // Uniforms buffer
                .binding = 0,
                .visibility = c.WGPUShaderStage_VERTEX,
                .ty = c.WGPUBindingType_UniformBuffer,

                .has_dynamic_offset = false,
                .min_buffer_binding_size = 0,

                .multisampled = undefined,
                .view_dimension = undefined,
                .texture_component_type = undefined,
                .storage_texture_format = undefined,
                .count = undefined,
            },
            (c.WGPUBindGroupLayoutEntry){
                .binding = 1,
                .visibility = c.WGPUShaderStage_FRAGMENT,
                .ty = c.WGPUBindingType_SampledTexture,

                .multisampled = false,
                .view_dimension = c.WGPUTextureViewDimension._D2,
                .texture_component_type = c.WGPUTextureComponentType._Uint,
                .storage_texture_format = c.WGPUTextureFormat._Rgba8Unorm,

                .count = undefined,
                .has_dynamic_offset = undefined,
                .min_buffer_binding_size = undefined,
            },
            (c.WGPUBindGroupLayoutEntry){
                .binding = 2,
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
        };
        const bind_group_layout = c.wgpu_device_create_bind_group_layout(
            device,
            &(c.WGPUBindGroupLayoutDescriptor){
                .label = "gui bind group",
                .entries = &bind_group_layout_entries,
                .entries_length = bind_group_layout_entries.len,
            },
        );
        const bind_group_layouts = [_]c.WGPUBindGroupId{bind_group_layout};

        ////////////////////////////////////////////////////////////////////////////
        // Vertex buffers (new!)
        const vertex_buffer_attributes = [_]c.WGPUVertexAttributeDescriptor{
            // position
            .{ .offset = 0, .format = c.WGPUVertexFormat._Float2, .shader_location = 0 },
            // uv
            .{ .offset = 8, .format = c.WGPUVertexFormat._Float2, .shader_location = 1 },
            // color
            .{ .offset = 16, .format = c.WGPUVertexFormat._Float4, .shader_location = 2 },
        };
        const vertex_buffer_layout_entries = [_]c.WGPUVertexBufferLayoutDescriptor{
            .{
                .array_stride = 0,
                .step_mode = c.WGPUInputStepMode._Vertex,
                .attributes = &vertex_buffer_attributes,
                .attributes_length = vertex_buffer_attributes.len,
            },
        };
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
                    .vertex_buffers = &vertex_buffer_layout_entries,
                    .vertex_buffers_length = vertex_buffer_layout_entries.len,
                },
                .sample_count = 1,
                .sample_mask = 0,
                .alpha_to_coverage_enabled = false,
            },
        );

        ////////////////////////////////////////////////////////////////////////

        var out = Gui{
            .ctx = ctx,
            .time_ms = null,

            .device = device,
            .queue = queue,

            .bind_group_layout = bind_group_layout,

            .font_tex = font_tex,
            .font_tex_view = font_tex_view,

            .tex_sampler = tex_sampler,

            .uniform_buf = uniform_buf,

            // Populated in ensure_buf_size_ below
            .vertex_buf = undefined,
            .vertex_buf_size = 0,
            .index_buf = undefined,
            .index_buf_size = 0,

            .render_pipeline = render_pipeline,
        };

        // Create the initial vertices and bind groups
        out.ensure_buf_size_(1, 1, false);

        return out;
    }

    fn bind_group_for(self: *Self, tex_view: c.WGPUTextureViewId) c.WGPUBindGroupId {
        const bind_group_entries = [_]c.WGPUBindGroupEntry{
            (c.WGPUBindGroupEntry){
                .binding = 0,
                .buffer = self.uniform_buf,
                .offset = 0,
                .size = @sizeOf(f32) * 4 * 4,

                .sampler = 0, // None
                .texture_view = 0, // None
            },
            (c.WGPUBindGroupEntry){
                .binding = 1,
                .texture_view = tex_view,
                .sampler = 0, // None
                .buffer = 0, // None

                .offset = undefined,
                .size = undefined,
            },
            (c.WGPUBindGroupEntry){
                .binding = 2,
                .sampler = self.tex_sampler,
                .texture_view = 0, // None
                .buffer = 0, // None

                .offset = undefined,
                .size = undefined,
            },
        };
        return c.wgpu_device_create_bind_group(
            self.device,
            &(c.WGPUBindGroupDescriptor){
                .label = "gui bind group",
                .layout = self.bind_group_layout,
                .entries = &bind_group_entries,
                .entries_length = bind_group_entries.len,
            },
        );
    }

    pub fn deinit(self: *Self) void {
        c.igDestroyContext(self.ctx);
        c.wgpu_buffer_destroy(self.uniform_buf);
        c.wgpu_bind_group_layout_destroy(self.bind_group_layout);
        c.wgpu_texture_destroy(self.font_tex);
        c.wgpu_texture_view_destroy(self.font_tex_view);
        c.wgpu_sampler_destroy(self.tex_sampler);
        c.wgpu_buffer_destroy(self.vertex_buf);
        c.wgpu_buffer_destroy(self.index_buf);
        c.wgpu_render_pipeline_destroy(self.render_pipeline);
    }

    pub fn ensure_buf_size_(self: *Self, num_vert: usize, num_index: usize, del_prev_buf: bool) void {
        if (num_vert <= self.vertex_buf_size and num_index <= self.index_buf_size) {
            return;
        }
        if (num_vert > self.vertex_buf_size) {
            // Regenerate vertex buf
            if (del_prev_buf) {
                c.wgpu_buffer_destroy(self.vertex_buf);
            }
            self.vertex_buf_size = num_vert;
            self.vertex_buf = c.wgpu_device_create_buffer(
                self.device,
                &(c.WGPUBufferDescriptor){
                    .label = "gui vertices",
                    .size = @sizeOf(c.ImDrawVert) * num_vert, // pos2, uv2, color4
                    .usage = c.WGPUBufferUsage_VERTEX | c.WGPUBufferUsage_COPY_DST,
                    .mapped_at_creation = false,
                },
            );
        }
        if (num_index > self.index_buf_size) {
            // Regenerate index buf
            if (del_prev_buf) {
                c.wgpu_buffer_destroy(self.index_buf);
            }
            self.index_buf = c.wgpu_device_create_buffer(
                self.device,
                &(c.WGPUBufferDescriptor){
                    .label = "gui indexes",
                    .size = @sizeOf(c.ImDrawIdx) * num_index,
                    .usage = c.WGPUBufferUsage_INDEX | c.WGPUBufferUsage_COPY_DST,
                    .mapped_at_creation = false,
                },
            );
            self.index_buf_size = num_index;
        }
    }

    pub fn ensure_buf_size(self: *Self, num_vert: usize, num_index: usize) void {
        self.ensure_buf_size_(num_vert, num_index, true);
    }

    pub fn new_frame(
        self: *Self,
        win_width: c_int,
        win_height: c_int,
        density: c_int,
    ) void {
        var io = c.igGetIO();
        std.debug.assert(c.ImFontAtlas_IsBuilt(io.*.Fonts));

        io.*.DisplaySize = c.ImVec2{
            .x = @intToFloat(f32, win_width),
            .y = @intToFloat(f32, win_height),
        };
        io.*.DisplayFramebufferScale = c.ImVec2{
            .x = @intToFloat(f32, density),
            .y = @intToFloat(f32, density),
        };

        const now_ms = std.time.milliTimestamp();
        if (self.time_ms) |t| {
            io.*.DeltaTime = std.math.min(1.0 / 60., @intToFloat(f32, now_ms - t) / 1000.0);
        } else {
            io.*.DeltaTime = 1.0 / 60.0;
        }
        self.time_ms = now_ms;

        c.igNewFrame();
    }

    pub fn draw(
        self: *Self,
        next_texture: c.WGPUSwapChainOutput,
        cmd_encoder: c.WGPUCommandEncoderId,
    ) void {
        c.igRender();
        var draw_data = c.igGetDrawData();
        self.render_draw_data(next_texture, cmd_encoder, draw_data);
    }

    fn setup_render_state(self: *Self, draw_data: [*c]c.ImDrawData) void {
        const L = draw_data.*.DisplayPos.x;
        const R = draw_data.*.DisplayPos.x + draw_data.*.DisplaySize.x;
        const T = draw_data.*.DisplayPos.y;
        const B = draw_data.*.DisplayPos.y + draw_data.*.DisplaySize.y;

        const ortho_projection: [4][4]f32 = .{
            .{ 2.0 / (R - L), 0.0, 0.0, 0.0 },
            .{ 0.0, 2.0 / (T - B), 0.0, 0.0 },
            .{ 0.0, 0.0, -1.0, 0.0 },
            .{ (R + L) / (L - R), (T + B) / (B - T), 0.0, 1.0 },
        };

        std.debug.assert(@sizeOf(@TypeOf(ortho_projection)) == 4 * 4 * 4);
        c.wgpu_queue_write_buffer(
            self.queue,
            self.uniform_buf,
            0,
            @ptrCast([*c]const u8, &ortho_projection),
            @sizeOf(@TypeOf(ortho_projection)),
        );
        return;
    }

    fn render_draw_data(
        self: *Self,
        next_texture: c.WGPUSwapChainOutput,
        cmd_encoder: c.WGPUCommandEncoderId,
        draw_data: [*c]c.ImDrawData,
    ) void {
        self.setup_render_state(draw_data);

        // Render to the main view
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
        var n: usize = 0;
        while (n < draw_data.*.CmdListsCount) : (n += 1) {
            const cmd_list = draw_data.*.CmdLists[n];

            // Copy this draw list data into the buffers, after making sure
            // that they're large enough
            self.ensure_buf_size(
                @intCast(usize, cmd_list.*.VtxBuffer.Size),
                @intCast(usize, cmd_list.*.IdxBuffer.Size),
            );
            c.wgpu_queue_write_buffer(
                self.queue,
                self.vertex_buf,
                0,
                @ptrCast([*c]const u8, cmd_list.*.VtxBuffer.Data),
                @intCast(usize, cmd_list.*.VtxBuffer.Size) * @sizeOf(c.ImDrawVert),
            );
            c.wgpu_queue_write_buffer(
                self.queue,
                self.index_buf,
                0,
                @ptrCast([*c]const u8, cmd_list.*.IdxBuffer.Data),
                @intCast(usize, cmd_list.*.IdxBuffer.Size) * @sizeOf(c.ImDrawIdx),
            );

            var cmd_i: usize = 0;
            while (cmd_i < cmd_list.*.CmdBuffer.Size) : (cmd_i += 1) {
                const pcmd = &cmd_list.*.CmdBuffer.Data[cmd_i];
                std.debug.assert(pcmd.*.UserCallback == null);

                const rpass = c.wgpu_command_encoder_begin_render_pass(
                    cmd_encoder,
                    &(c.WGPURenderPassDescriptor){
                        .color_attachments = &color_attachments,
                        .color_attachments_length = color_attachments.len,
                        .depth_stencil_attachment = null,
                    },
                );
                const bind_group = self.bind_group_for(@intCast(c.WGPUTextureViewId, @ptrToInt(pcmd.*.TextureId)));
                defer c.wgpu_bind_group_destroy(bind_group);

                c.wgpu_render_pass_set_pipeline(rpass, self.render_pipeline);
                c.wgpu_render_pass_set_vertex_buffer(rpass, 0, self.vertex_buf, 0, self.vertex_buf_size); // TODO
                c.wgpu_render_pass_set_index_buffer(rpass, self.index_buf, 0, self.index_buf_size); // TODO
                c.wgpu_render_pass_set_bind_group(rpass, 0, bind_group, null, 0);
                c.wgpu_render_pass_draw(rpass, 3, 1, 0, 0);
                c.wgpu_render_pass_end_pass(rpass);
            }
        }
    }

    //////////////////////////////////////////////////////////////////////////
    // GUI callbacks
    pub fn scroll(self: *Self, x_offset: f32, y_offset: f32) void {
        var io = c.igGetIO();
        io.*.MouseWheelH += x_offset;
        io.*.MouseWheel += y_offset;
    }
};
