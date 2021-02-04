const std = @import("std");

const c = @import("c.zig");
const util = @import("util.zig");

// TODO: calculate this whole error and function below at comptime
const CompilationError = error{
    // Success = 0
    InvalidStage,
    CompilationError,
    InternalError,
    NullResultObject,
    InvalidAssembly,
    ValidationError,
    TransformationError,
    ConfigurationError,

    UnknownError,
};
fn status_to_err(i: c_int) CompilationError {
    switch (i) {
        c.shaderc_compilation_status_invalid_stage => return CompilationError.InvalidStage,
        c.shaderc_compilation_status_compilation_error => return CompilationError.CompilationError,
        c.shaderc_compilation_status_internal_error => return CompilationError.InternalError,
        c.shaderc_compilation_status_null_result_object => return CompilationError.NullResultObject,
        c.shaderc_compilation_status_invalid_assembly => return CompilationError.InvalidAssembly,
        c.shaderc_compilation_status_validation_error => return CompilationError.ValidationError,
        c.shaderc_compilation_status_transformation_error => return CompilationError.TransformationError,
        c.shaderc_compilation_status_configuration_error => return CompilationError.ConfigurationError,
        else => return CompilationError.UnknownError,
    }
}

export fn include_cb(
    user_data: ?*c_void,
    requested_source: [*c]const u8,
    include_type: c_int,
    requesting_source: [*c]const u8,
    include_depth: usize,
) *c.shaderc_include_result {
    const alloc = @ptrCast(*std.mem.Allocator, @alignCast(8, user_data));
    var out = alloc.create(c.shaderc_include_result) catch |err| {
        std.debug.panic("Could not allocate shaderc_include_result: {}", .{err});
    };
    out.* = (c.shaderc_include_result){
        .user_data = user_data,
        .source_name = "",
        .source_name_length = 0,
        .content = null,
        .content_length = 0,
    };

    const name = std.mem.spanZ(requested_source);
    const file = std.fs.cwd().openFile(name, std.fs.File.OpenFlags{ .read = true }) catch |err| {
        const msg = std.fmt.allocPrint(alloc, "{}", .{err}) catch |err2| {
            std.debug.panic("Could not allocate error message: {}", .{err2});
        };
        out.content = msg.ptr;
        out.content_length = msg.len;

        return out;
    };
    defer file.close();

    const size = file.getEndPos() catch |err| {
        std.debug.panic("Could not get end position of file: {}", .{err});
    };
    const buf = alloc.alloc(u8, size) catch |err| {
        std.debug.panic("Could not allocate space for data: {}", .{err});
    };
    _ = file.readAll(buf) catch |err| {
        std.debug.panic("Could not read header: {}", .{err});
    };

    out.source_name = requested_source;
    out.source_name_length = name.len;
    out.content = buf.ptr;
    out.content_length = buf.len;
    return out;
}

export fn include_release_cb(user_data: ?*c_void, include_result: ?*c.shaderc_include_result) void {
    // We don't need to do anything here, because we're using an arena allocator
}

pub fn build_shader_from_file(alloc: *std.mem.Allocator, comptime name: []const u8) ![]u32 {
    const buf = try util.file_contents(alloc, name);
    return build_shader(alloc, name, buf);
}

pub fn build_shader(alloc: *std.mem.Allocator, name: []const u8, src: []const u8) ![]u32 {
    var arena = std.heap.ArenaAllocator.init(alloc);
    var tmp_alloc: *std.mem.Allocator = &arena.allocator;
    defer arena.deinit();

    const compiler = c.shaderc_compiler_initialize();
    defer c.shaderc_compiler_release(compiler);

    const options = c.shaderc_compile_options_initialize();
    defer c.shaderc_compile_options_release(options);
    c.shaderc_compile_options_set_include_callbacks(
        options,
        include_cb,
        include_release_cb,
        tmp_alloc,
    );

    const result = c.shaderc_compile_into_spv(
        compiler,
        src.ptr,
        src.len,
        c.shaderc_shader_kind.shaderc_glsl_infer_from_source,
        name.ptr,
        "main",
        options,
    );
    defer c.shaderc_result_release(result);
    const r = c.shaderc_result_get_compilation_status(result);
    if (@enumToInt(r) != c.shaderc_compilation_status_success) {
        const err = c.shaderc_result_get_error_message(result);
        std.debug.warn("Shader error: {} {s}\n", .{ r, err });
        return status_to_err(@enumToInt(r));
    }

    // Copy the result out of the shader
    const len = c.shaderc_result_get_length(result);
    std.debug.assert(len % 4 == 0);
    const out = alloc.alloc(u32, len / 4) catch unreachable;
    @memcpy(@ptrCast([*]u8, out.ptr), c.shaderc_result_get_bytes(result), len);

    return out;
}

////////////////////////////////////////////////////////////////////////////////

pub const LineErr = struct {
    msg: []const u8,
    line: ?u32,
};
pub const Error = struct {
    errs: []const LineErr,
    code: c.shaderc_compilation_status,
};
pub const Shader = struct {
    spirv: []const u32,
    has_time: bool,
};

pub const Result = union(enum) {
    Shader: Shader,
    Error: Error,

    pub fn deinit(self: Result, alloc: *std.mem.Allocator) void {
        switch (self) {
            .Shader => |d| alloc.free(d.spirv),
            .Error => |e| {
                for (e.errs) |r| {
                    alloc.free(r.msg);
                }
                alloc.free(e.errs);
            },
        }
    }
};
