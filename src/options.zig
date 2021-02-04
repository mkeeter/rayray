const std = @import("std");

pub const Options = struct {
    total_samples: ?u32,
    width: u32,
    height: u32,
    spectral: bool,

    fn print_help() !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("rayray [-h] [-n total_samples]\n", .{});
    }
    pub fn parse_args(alloc: *std.mem.Allocator) !Options {
        const args = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, args);

        var out = Options{
            .total_samples = null,
            .width = 600,
            .height = 623, // includes menu height
            .spectral = false,
        };
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "-h")) {
                try print_help();
                std.process.exit(0);
            } else if (std.mem.eql(u8, args[i], "-n")) {
                i += 1;
                if (i == args.len) {
                    std.debug.print("Error: missing value for -n", .{});
                    std.process.exit(1);
                } else {
                    if (std.fmt.parseUnsigned(u32, args[i], 10)) |s| {
                        out.total_samples = s;
                    } else |err| {
                        std.debug.print("Error: {} is not an integer", .{args[i]});
                        std.process.exit(1);
                    }
                }
            } else if (std.mem.eql(u8, args[i], "-s")) {
                out.spectral = true;
            } else {
                std.debug.print("Unknown option: {s}", .{args[i]});
                std.process.exit(1);
            }
        }

        return out;
    }
};
