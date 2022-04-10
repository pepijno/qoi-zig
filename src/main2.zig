const std = @import("std");

const QOI_HEADER_SIZE: u32 = 14;
const QOI_PADDING: [8]u8 = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 1 };
const QOI_MAGIC: u32 = 0x716f6966; // characters "qoif" in hex
const QOI_OP_RUN: u8 = 0xc0;
const QOI_OP_INDEX: u8 = 0x00;
const QOI_OP_DIFF: u8 = 0x40;
const QOI_OP_LUMA: u8 = 0x80;
const QOI_OP_RGB: u8 = 0xfe;
const QOI_OP_RGBA: u8 = 0xff;

pub const QoiHeader = struct {
    const Self = @This();
    const magic = 0x716f6966; // characters "qoif" in hex
    const size = 14;

    width: u32,
    height: u32,
    channels: u8,
    colorspace: u8,

    fn encode(self: *Self) [size]u8 {
        var result: [size]u8 = undefined;
        std.mem.writeIntBig(u32, result[0..4], magic);
        std.mem.writeIntBig(u32, result[4..8], self.width);
        std.mem.writeIntBig(u32, result[8..12], self.height);
        result[12] = channels;
        result[13] = colorspace;
        return result;
    }

    fn decode(buffer: [size]u8) Self {
        // TODO: Check for header
        return Self {
            .width = std.mem.readIntBig(u32, buffer[4..8]),
            .heidht = std.mem.readIntBig(u32, buffer[8..12]),
            .channels = buffer[12],
            .colorspace = buffer[13]
        };
    }
};

const QoiRgba = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0xff,

    pub fn equals(self: QoiRgba, other: QoiRgba) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a;
    }

    pub fn hash(self: QoiRgba) u8 {
        return @intCast(u8, (3 * @intCast(u32, self.r) + 5 * @intCast(u32, self.g) + 7 * @intCast(u32, self.b) + 11 * @intCast(u32, self.a)) % 64);
    }
};

pub const ImageBuffer = struct {
    const Self = @This();
    bytes: []u8,
    index: usize,

    pub fn create(allocator: std.mem.Allocator, max_size: usize) !Self {
        return Self {
            .bytes = try allocator.alloc(u8, max_size),
            .index = 0,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
    }

    pub fn writeBytes(self: *Self, bytes: []const u8) void {
        std.mem.copy(u8, self.bytes[self.index..(self.index + bytes.len)], bytes[0..(bytes.len)]);
        self.index += bytes.len;
    }

    pub fn writeU32(self: *Self, int: u32) void {
        self.writeBytes(intToSlice(int)[0..]);
    }

    pub fn writeByte(self: *Self, byte: u8) void {
        self.bytes[self.index] = byte;
        self.index += 1;
    }

    pub fn writeOpRun(self: *Self, run: u8) void {
        self.writeByte(QOI_OP_RUN | (run - 1));
    }

    pub fn writeOpIndex(self: *Self, index: u8) void {
        self.writeByte(QOI_OP_INDEX | index);
    }

    pub fn writeOpRgb(self: *Self, color: QoiRgba) void {
        var bytes: [4]u8 = [_]u8{QOI_OP_RGB, color.r, color.g, color.b};
        self.writeBytes(bytes[0..]);
    }

    pub fn writeOpRgba(self: *Self, color: QoiRgba) void {
        var bytes: [5]u8 = [_]u8{QOI_OP_RGBA, color.r, color.g, color.b, color.a};
        self.writeBytes(bytes[0..]);
    }

    pub fn writeOpDiff(self: *Self, vr: i8, vg: i8, vb: i8) void {
        self.writeByte(QOI_OP_DIFF | @intCast(u8, vr + 2) << 4 | @intCast(u8, vg + 2) << 2 | @intCast(u8, vb + 2));
    }

    pub fn writeOpLuma(self: *Self, vg: i8, vg_r: i8, vg_b: i8) void {
        self.writeByte(QOI_OP_LUMA | @intCast(u8, vg + 32));
        self.writeByte(@intCast(u8, vg_r + 8) << 4 | @intCast(u8, vg_b + 8));
    }

    pub fn writeToFile(self: *Self, file: std.fs.File) !void {
        _ = try file.write(self.bytes[0..self.index]);
    }
};

fn intToSlice(int: u32) [4]u8 {
    return [4]u8{ @intCast(u8, (int & 0xff000000) >> 24), @intCast(u8, (int & 0x00ff0000) >> 16), @intCast(u8, (int & 0x0000ff00) >> 8), @intCast(u8, int & 0x000000ff) };
}

pub fn encode(allocator: std.mem.Allocator, qoi: QoiHeader, data: []const u8) !ImageBuffer {
    const max_size = qoi.width * qoi.height * (qoi.channels + 1) + QOI_HEADER_SIZE + QOI_PADDING.len;

    var image_buffer = try ImageBuffer.create(allocator, max_size);

    errdefer image_buffer.deinit();

    image_buffer.writeU32(QOI_MAGIC);
    image_buffer.writeU32(qoi.width);
    image_buffer.writeU32(qoi.height);
    image_buffer.writeByte(qoi.channels);
    image_buffer.writeByte(qoi.colorspace);

    var lookup = [_]QoiRgba{.{ .a = 0 }} ** 64;

    var prev_pixel = QoiRgba{
        .r = 0,
        .g = 0,
        .b = 0,
        .a = 0xff,
    };
    var current_pixel = prev_pixel;

    var pixel_length = qoi.width * qoi.height * qoi.channels;
    var pixel_end = pixel_length - qoi.channels;
    var channels = qoi.channels;

    var pixel_position: u32 = 0;
    var run: u6 = 0;

    while (pixel_position < pixel_length) {
        // if (channels == 4) {
        //     current_pixel =
        // } else {
        current_pixel.r = data[pixel_position + 0];
        current_pixel.g = data[pixel_position + 1];
        current_pixel.b = data[pixel_position + 2];
        current_pixel.a = data[pixel_position + 3];
        // }

        if (current_pixel.equals(prev_pixel)) {
            run += 1;

            if (run == 62 or pixel_position == pixel_end) {
                image_buffer.writeOpRun(run);
                run = 0;
            }
        } else {
            if (run > 0) {
                image_buffer.writeOpRun(run);
                run = 0;
            }

            var index_position = current_pixel.hash();

            if (lookup[index_position].equals(current_pixel)) {
                image_buffer.writeOpIndex(index_position);
            } else {
                lookup[index_position] = current_pixel;

                if (current_pixel.a == prev_pixel.a) {
                    var vr: i16 = @intCast(i16, current_pixel.r) - @intCast(i16, prev_pixel.r);
                    var vg: i16 = @intCast(i16, current_pixel.g) - @intCast(i16, prev_pixel.g);
                    var vb: i16 = @intCast(i16, current_pixel.b) - @intCast(i16, prev_pixel.b);

                    var vg_r: i16 = vr - vg;
                    var vg_b: i16 = vb - vg;

                    _ = vg_r;
                    _ = vg_b;

                    if (vr > -3 and vr < 2 and vg > -3 and vg < 2 and vb > -3 and vb < 2) {
                        image_buffer.writeOpDiff(@intCast(i8, vr), @intCast(i8, vg), @intCast(i8, vb));
                    } else if (vg_r > -9 and vg_r < 8 and vg > -33 and vg < 32 and vg_b > -9 and vg_b < 8) {
                        image_buffer.writeOpLuma(@intCast(i8, vg), @intCast(i8, vg_r), @intCast(i8, vg_b));
                    } else {
                        image_buffer.writeOpRgb(current_pixel);
                    }
                } else {
                    image_buffer.writeOpRgba(current_pixel);
                }
            }
        }
        prev_pixel = current_pixel;
        pixel_position += channels;
    }

    image_buffer.writeBytes(QOI_PADDING[0..]);

    return image_buffer;
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const raw_data = @embedFile("../data/zero.raw");

    var image_buffer = try encode(allocator, QoiHeader{
        .width = 512,
        .height = 512,
        .channels = 4,
        .colorspace = 0,
    }, std.mem.bytesAsSlice(u8, raw_data));

    defer image_buffer.deinit(allocator);

    const file = std.fs.cwd().createFile("converted.qoi", .{}) catch |err| label: {
        std.debug.print("unable to open file: {e}\n", .{err});
        const stderr = std.io.getStdErr();
        break :label stderr;
    };

    try image_buffer.writeToFile(file);

    // std.debug.print("length {} {}\n", .{ raw_data.len, res.len });

    std.log.info("All your codebase are belong to us.", .{});
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
