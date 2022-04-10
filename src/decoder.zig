const std = @import("std");
const header = @import("header.zig");
const Color = @import("color.zig").Color;
const ImageBuffer = @import("image-buffer.zig").ImageBuffer;

const QOI_OP_RUN: u8 = 0xC0;
const QOI_OP_INDEX: u8 = 0x00;
const QOI_OP_DIFF: u8 = 0x40;
const QOI_OP_LUMA: u8 = 0x80;
const QOI_OP_RGB: u8 = 0xFE;
const QOI_OP_RGBA: u8 = 0xFF;
const QOI_MASK: u8 = 0xC0;

fn add8(dst: *u8, diff: i8) void {
    dst.* +%= @bitCast(u8, diff);
}

fn unmapRange2(val: u32) i2 {
    return @intCast(i2, @as(i8, @truncate(u2, val)) - 2);
}

fn unmapRange4(val: u32) i4 {
    return @intCast(i4, @as(i8, @truncate(u4, val)) - 8);
}

fn unmapRange6(val: u32) i6 {
    return @intCast(i6, @as(i8, @truncate(u6, val)) - 32);
}

pub const Decoder = struct {
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

    pub fn decode(self: *Self, data: []const u8) ![]u8 {
        if (data.len < header.QoiHeader.size) {
            return error.InvalidData;
        }

        const qoi_header = try header.QoiHeader.decode(data[0..14].*);
        const channels = @enumToInt(qoi_header.channels);
        const pixel_length = qoi_header.width * qoi_header.height * channels;
        const chuncks_length = data.len - 8;

        var index = [_]Color{.{
            .r = 0,
            .g = 0,
            .b = 0,
            .a = 0,
        }} ** 64;
        var pixel = Color{
            .r = 0,
            .g = 0,
            .b = 0,
            .a = 0xFF,
        };

        var run: u6 = 0;
        var pixel_position: u32 = 0;
        var p: usize = 14;

        while (pixel_position < pixel_length) {
            if (run > 0) {
                run -= 1;
            } else if (p < chuncks_length) {
                var b1 = data[p];
                p += 1;

                if (b1 == QOI_OP_RGB) {
                    pixel.r = data[p + 0];
                    pixel.g = data[p + 1];
                    pixel.b = data[p + 2];
                    p += 3;
                } else if (b1 == QOI_OP_RGBA) {
                    pixel.r = data[p + 0];
                    pixel.g = data[p + 1];
                    pixel.b = data[p + 2];
                    pixel.a = data[p + 3];
                    p += 4;
                } else if ((b1 & QOI_MASK) == QOI_OP_INDEX) {
                    pixel = index[b1];
                } else if ((b1 & QOI_MASK) == QOI_OP_DIFF) {
                    const diff_r = unmapRange2(b1 >> 4);
                    const diff_g = unmapRange2(b1 >> 2);
                    const diff_b = unmapRange2(b1 >> 0);

                    add8(&pixel.r, diff_r);
                    add8(&pixel.g, diff_g);
                    add8(&pixel.b, diff_b);
                } else if ((b1 & QOI_MASK) == QOI_OP_LUMA) {
                    var b2 = data[p];
                    p += 1;

                    const diff_rg = unmapRange4(b2 >> 4);
                    const diff_rb = unmapRange4(b2 >> 0);

                    const diff_g = unmapRange6(b1);
                    const diff_r = @as(i8, diff_g) + diff_rg;
                    const diff_b = @as(i8, diff_g) + diff_rb;

                    add8(&pixel.r, diff_r);
                    add8(&pixel.g, diff_g);
                    add8(&pixel.b, diff_b);
                } else if ((b1 & QOI_MASK) == QOI_OP_RUN) {
                    run = @intCast(u6, b1 & 0x3F);
                }

                index[pixel.hash()] = pixel;
            }

            if (channels == 4) {
                const bytes = [_]u8{ pixel.r, pixel.g, pixel.b, pixel.a };
                try self.buffer.writeBytes(&bytes);
            } else {
                const bytes = [_]u8{ pixel.r, pixel.g, pixel.b };
                try self.buffer.writeBytes(&bytes);
            }

            pixel_position += channels;
        }

        _ = qoi_header;
        return self.buffer.asSlice();
    }
};

test "can decode qoi image" {
    var decoder = Decoder.init(std.testing.allocator);
    defer decoder.deinit();

    const src_data = @embedFile("../data/zero.qoi");

    const res = try decoder.decode(std.mem.bytesAsSlice(u8, src_data));
    defer std.testing.allocator.free(res);

    const ref_data = @embedFile("../data/zero.raw");
    try std.testing.expectEqualSlices(u8, ref_data, res);
}
