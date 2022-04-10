const std = @import("std");
const header = @import("header.zig");
const ImageBuffer = @import("image-buffer.zig").ImageBuffer;
const Decoder = @import("decoder.zig").Decoder;
const Encoder = @import("encoder.zig").Encoder;
const clap = @import("clap");
const zigimg = @import("zigimg");

fn printUsage() !void {
    _ = try std.io.getStdErr().writer().write("usage: qoi-zig <INPUT> <OUTPUT>\n");
    _ = try std.io.getStdErr().writer().write("Examples:\n");
    _ = try std.io.getStdErr().writer().write("\tqoi-zig input.png output.qoi\n");
    _ = try std.io.getStdErr().writer().write("\tqoi-zig input.qoi output.png\n");
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("<POS>...") catch unreachable,
    };

    var diag = clap.Diagnostic{};
    var args = clap.parse(clap.Help, &params, .{ .diagnostic = &diag }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer args.deinit();

    if (args.positionals().len != 2) {
        try printUsage();
        return 1;
    }

    const in_path = args.positionals()[0];
    const out_path = args.positionals()[1];

    const in_ext = std.fs.path.extension(in_path);
    const out_ext = std.fs.path.extension(out_path);

    if (!(std.mem.eql(u8, in_ext, ".qoi") and std.mem.eql(u8, out_ext, ".png")) and !(std.mem.eql(u8, in_ext, ".png") and std.mem.eql(u8, out_ext, ".qoi"))) {
        try printUsage();
        return 1;
    }

    if (std.mem.eql(u8, in_ext, ".qoi")) {
        var file = try std.fs.cwd().openFile(in_path, .{});
        defer file.close();

        const buffer_size = 2000000;
        const file_buffer = try file.readToEndAlloc(allocator, buffer_size);
        defer allocator.free(file_buffer);

        var decoder = Decoder.init(allocator);
        defer decoder.deinit();

        const decoded = try decoder.decode(file_buffer);
        defer allocator.free(decoded);

        var out_file = try std.fs.cwd().createFile(out_path, .{});
        _ = try out_file.write(decoded);
    } else {
        var file = try zigimg.Image.fromFilePath(allocator, in_path);
        defer file.deinit();

        const bytes = try file.rawBytes();
        const pixel_format = file.pixelFormat();
        const channels = if (pixel_format == zigimg.PixelFormat.Rgb24) header.Channels.RGB else header.Channels.RGBA;

        var h = header.QoiHeader {
            .width = try std.math.cast(u32, file.width),
            .height = try std.math.cast(u32, file.height),
            .channels = channels,
            .colorspace = header.Colorspace.sRGB,
        };

        var encoder = Encoder.init(allocator);
        defer encoder.deinit();

        const encoded = try encoder.encode(&h, bytes);
        defer allocator.free(encoded);

        var out_file = try std.fs.cwd().createFile(out_path, .{});
        _ = try out_file.write(encoded);
    }

    return 0;
}

test "" {
    _ = @import("header.zig");
    _ = @import("image-buffer.zig");
    _ = @import("color.zig");
    _ = @import("encoder.zig");
    _ = @import("decoder.zig");
}
