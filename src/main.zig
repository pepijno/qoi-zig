const std = @import("std");
const header = @import("header.zig");
const ImageBuffer = @import("image-buffer.zig").ImageBuffer;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var qoi_header = header.QoiHeader {
        .width = 512,
        .height = 512,
        .channels = header.Channels.RGBA,
        .colorspace = header.Colorspace.sRGB,
    };

    const encoded = qoi_header.encode();
    var buffer = ImageBuffer.init(allocator);
    defer buffer.deinit();

    try buffer.writeBytes(&encoded);

    const res = buffer.asSlice();
    defer allocator.free(res);

    std.debug.print("{}", .{res.len});
}

test "" {
    _ = @import("header.zig");
    _ = @import("image-buffer.zig");
    _ = @import("color.zig");
    _ = @import("encoder.zig");
}
