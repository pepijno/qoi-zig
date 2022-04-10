const std = @import("std");
const header = @import("header.zig");
const ImageBuffer = @import("image-buffer.zig").ImageBuffer;
const Decoder = @import("decoder.zig").Decoder;
const Encoder = @import("encoder.zig").Encoder;
const clap = @import("clap");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help             Display this help and exit.              ") catch unreachable,
        clap.parseParam("-n, --number <NUM>     An option parameter, which takes a value.") catch unreachable,
        clap.parseParam("-s, --string <STR>...  An option parameter which can be specified multiple times.") catch unreachable,
        clap.parseParam("<POS>...") catch unreachable,
    };

    var diag = clap.Diagnostic{};
    var args = clap.parse(clap.Help, &params, .{ .diagnostic = &diag }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer args.deinit();

    if (args.positionals().len != 2) {
        return 1;
    }

    const in_path = args.positionals()[0];
    const out_path = args.positionals()[1];

    const in_ext = std.fs.path.extension(in_path);
    const out_ext = std.fs.path.extension(out_path);

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
    } else if (std.mem.eql(u8, out_ext, ".qoi")) {
        var file = try std.fs.cwd().openFile(in_path, .{});
        defer file.close();

        const buffer_size = 2000000;
        const file_buffer = try file.readToEndAlloc(allocator, buffer_size);
        defer allocator.free(file_buffer);

        var encoder = Encoder.init(allocator);
        defer encoder.deinit();

        const h = header.QoiHeader {
            .width = 512,
            .height = 512,
            .channels = header.Channels.RGBA,
            .colorspace = header.Colorspace.sRGB,
        };

        const encoded = try encoder.encode(&h, file_buffer);
        defer allocator.free(encoded);

        var out_file = try std.fs.cwd().createFile(out_path, .{});
        _ = try out_file.write(encoded);
    }

    // if (args.flag("--help"))
    //     // return clap.help(std.io.getStdErr().writer(), &params);
    //     return clap.usage(std.io.getStdErr().writer(), &params);
    // if (args.option("--number")) |n|
    //     std.debug.print("--number = {s}\n", .{n});
    // for (args.options("--string")) |s|
    //     std.debug.print("--string = {s}\n", .{s});
    // for (args.positionals()) |pos|
    //     std.debug.print("{s}\n", .{pos});

    return 0;
}

test "" {
    _ = @import("header.zig");
    _ = @import("image-buffer.zig");
    _ = @import("color.zig");
    _ = @import("decoder.zig");
    _ = @import("decoder.zig");
}
