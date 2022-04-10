const std = @import("std");
const header = @import("header.zig");
const ImageBuffer = @import("image-buffer.zig").ImageBuffer;
const Color = @import("color.zig").Color;

const QOI_PADDING: [8]u8 = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 1};

pub const Encoder = struct {
    const Self = @This();

    buffer: ImageBuffer,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .buffer = ImageBuffer.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn encode(self: *Self, qoi_header: *const header.QoiHeader, data: []const u8) ![]u8 {
        const header_bytes = qoi_header.encode();
        try self.buffer.writeBytes(&header_bytes);

        var index = [_]Color{.{
            .r = 0,
            .g = 0,
            .b = 0,
            .a = 0,
        }} ** 64;

        var prev_pixel = Color{
            .r = 0,
            .g = 0,
            .b = 0,
            .a = 0xFF,
        };
        var current_pixel = prev_pixel;

        const channels = @enumToInt(qoi_header.channels);
        const pixel_length = qoi_header.width * qoi_header.height * channels;
        const pixel_end = pixel_length - channels;

        var pixel_position: u32 = 0;
        var run: u6 = 0;

        while (pixel_position < pixel_length) {
            current_pixel.r = data[pixel_position + 0];
            current_pixel.g = data[pixel_position + 1];
            current_pixel.b = data[pixel_position + 2];
            if (channels == 4) {
                current_pixel.a = data[pixel_position + 3];
            }

            if (current_pixel.equals(prev_pixel)) {
                run += 1;

                if (run == 62 or pixel_position == pixel_end) {
                    try self.buffer.opRun(run);
                    run = 0;
                }
            } else {
                if (run > 0) {
                    try self.buffer.opRun(run);
                    run = 0;
                }

                var index_position = current_pixel.hash();

                if (index[index_position].equals(current_pixel)) {
                    try self.buffer.opIndex(index_position);
                } else {
                    index[index_position] = current_pixel;

                    if (current_pixel.a == prev_pixel.a) {
                        var vr: i16 = @intCast(i16, current_pixel.r) - @intCast(i16, prev_pixel.r);
                        var vg: i16 = @intCast(i16, current_pixel.g) - @intCast(i16, prev_pixel.g);
                        var vb: i16 = @intCast(i16, current_pixel.b) - @intCast(i16, prev_pixel.b);

                        var vg_r: i16 = vr - vg;
                        var vg_b: i16 = vb - vg;

                        if (vr > -3 and vr < 2 and vg > -3 and vg < 2 and vb > -3 and vb < 2) {
                            try self.buffer.opDiff(@intCast(i8, vr), @intCast(i8, vg), @intCast(i8, vb));
                        } else if (vg_r > -9 and vg_r < 8 and vg > -33 and vg < 32 and vg_b > -9 and vg_b < 8) {
                            try self.buffer.opLuma(@intCast(i8, vg), @intCast(i8, vg_r), @intCast(i8, vg_b));
                        } else {
                            try self.buffer.opRgb(current_pixel);
                        }
                    } else {
                        try self.buffer.opRgba(current_pixel);
                    }
                }
            }

            prev_pixel = current_pixel;
            pixel_position += channels;
        }

        try self.buffer.writeBytes(&QOI_PADDING);

        return self.buffer.asSlice();
    }
};

test "can encode raw image" {
    var encoder = Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    const src_data = @embedFile("../data/zero.raw");
    var qoi_header = header.QoiHeader{
        .width = 512,
        .height = 512,
        .channels = header.Channels.RGBA,
        .colorspace = header.Colorspace.sRGB,
    };

    const res = try encoder.encode(&qoi_header, std.mem.bytesAsSlice(u8, src_data));
    defer std.testing.allocator.free(res);

    const ref_data = @embedFile("../data/zero.qoi");
    try std.testing.expectEqualSlices(u8, ref_data, res);
}
