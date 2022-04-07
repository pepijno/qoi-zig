const std = @import("std");
const header = @import("header");

pub fn main() anyerror!void {
    var qoi_header = header.QoiHeader {
        .width = 512,
        .height = 512,
        .channels = header.Channels.RGBA,
        .colorspace = header.Colorspace.sRGB,
    };

    const buffer = qoi_header.encode();

    std.debug.print("{}", .{buffer.len});
}

test "" {
    _ = @import("header");
}
