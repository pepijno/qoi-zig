const std = @import("std");

pub const Colorspace = enum(u8) {
    sRGB = 0,
    linear = 1,
};

pub const Channels = enum(u8) {
    RGB = 3,
    RGBA = 4,
};

pub const QoiHeader = struct {
    const Self = @This();
    const magic = 0x716F6966; // characters "qoif" in hex
    pub const size = 14;

    width: u32,
    height: u32,
    channels: Channels,
    colorspace: Colorspace,

    pub fn encode(self: *Self) [size]u8 {
        var result: [size]u8 = undefined;
        std.mem.writeIntBig(u32, result[0..4], magic);
        std.mem.writeIntBig(u32, result[4..8], self.width);
        std.mem.writeIntBig(u32, result[8..12], self.height);
        result[12] = @enumToInt(self.channels);
        result[13] = @enumToInt(self.colorspace);
        return result;
    }

    pub fn decode(buffer: [size]u8) !Self {
        if (std.mem.readIntBig(u32, buffer[0..4]) != magic) {
            return error.InvalidMagic;
        }
        return Self {
            .width = std.mem.readIntBig(u32, buffer[4..8]),
            .height = std.mem.readIntBig(u32, buffer[8..12]),
            .channels = @intToEnum(Channels, buffer[12]),
            .colorspace = @intToEnum(Colorspace, buffer[13]),
        };
    }
};

test "encoding QoiHeader" {
    var header = QoiHeader {
        .width = 1000,
        .height = 2000,
        .channels = Channels.RGBA,
        .colorspace = Colorspace.sRGB,
    };

    const encoded = header.encode();

    const expected = [14]u8{
        0x71, 0x6F, 0x69, 0x66, // magic
        0x00, 0x00, 0x03, 0xE8, // width
        0x00, 0x00, 0x07, 0xD0, // height
        0x4, // channels
        0x0, // colorspace
    };
    try std.testing.expectEqual(expected, encoded);
}

test "decoding QoiHeader" {
    const encoded = [14]u8{
        0x71, 0x6F, 0x69, 0x66, // magic
        0x00, 0x00, 0x10, 0x00, // width
        0x00, 0x00, 0x02, 0x00, // height
        0x3, // channels
        0x1, // colorspace
    };

    const header = try QoiHeader.decode(encoded);

    const expected = QoiHeader {
        .width = 4096,
        .height = 512,
        .channels = Channels.RGB,
        .colorspace = Colorspace.linear,
    };

    try std.testing.expectEqual(expected, header);
}

test "decoding QoiHeader with wrong magic fails" {
    const encoded = [14]u8{
        0x11, 0x6F, 0x69, 0x66, // wrong magic in first byte
        0x00, 0x00, 0x10, 0x00, // width
        0x00, 0x00, 0x02, 0x00, // height
        0x3, // channels
        0x1, // colorspace
    };

    const err = QoiHeader.decode(encoded);

    try std.testing.expectError(error.InvalidMagic, err);
}
