const std = @import("std");
const Color = @import("color.zig").Color;

const QOI_OP_RUN: u8 = 0xC0;
const QOI_OP_INDEX: u8 = 0x00;
const QOI_OP_DIFF: u8 = 0x40;
const QOI_OP_LUMA: u8 = 0x80;
const QOI_OP_RGB: u8 = 0xFE;
const QOI_OP_RGBA: u8 = 0xFF;

pub const ImageBuffer = struct {
    const Self = @This();
    bytes: std.ArrayList(u8),
    index: usize,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .bytes = std.ArrayList(u8).init(allocator),
            .index = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.bytes.deinit();
    }

    fn writeByte(self: *Self, byte: u8) !void {
        try self.bytes.append(byte);
    }

    pub fn asSlice(self: *Self) []u8 {
        return self.bytes.toOwnedSlice();
    }

    pub fn writeBytes(self: *Self, bytes: []const u8) !void {
        try self.bytes.appendSlice(bytes);
    }

    pub fn opRun(self: *Self, run: u6) !void {
        const byte = QOI_OP_RUN | @intCast(u8, run - 1);
        try self.writeByte(byte);
    }

    pub fn opIndex(self: *Self, index: u6) !void {
        const byte = QOI_OP_INDEX | index;
        try self.writeByte(byte);
    }

    pub fn opDiff(self: *Self, vr: i8, vg: i8, vb: i8) !void {
        const byte = QOI_OP_DIFF
            | @intCast(u8, vr + 2) << 4
            | @intCast(u8, vg + 2) << 2
            | @intCast(u8, vb + 2);
        try self.writeByte(byte);
    }

    pub fn opLuma(self: *Self, vg: i8, vg_r: i8, vg_b: i8) !void {
        const bytes = [_]u8 {
            QOI_OP_LUMA | @intCast(u8, vg + 32),
            @intCast(u8, vg_r + 8) << 4 | @intCast(u8, vg_b + 8),
        };
        try self.writeBytes(&bytes);
    }

    pub fn opRgb(self: *Self, color: Color) !void {
        const bytes = [_]u8{ QOI_OP_RGB, color.r, color.g, color.b };
        try self.writeBytes(&bytes);
    }

    pub fn opRgba(self: *Self, color: Color) !void {
        const bytes = [_]u8{ QOI_OP_RGBA, color.r, color.g, color.b, color.a };
        try self.writeBytes(&bytes);
    }
};

test "can write multiple bytes to buffer" {
    var image_buffer = ImageBuffer.init(std.testing.allocator);
    defer image_buffer.deinit();

    const bytes = [_]u8{ 0x10, 0x20, 0x30, 0x40 };
    try image_buffer.writeBytes(bytes[0..]);
    const result = image_buffer.asSlice();
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualSlices(u8, &bytes, result);
}

test "can write OP_RUN" {
    var image_buffer = ImageBuffer.init(std.testing.allocator);
    defer image_buffer.deinit();

    try image_buffer.opRun(23);
    const result = image_buffer.asSlice();
    defer std.testing.allocator.free(result);

    const expected = [_]u8{ 0xd6 };

    try std.testing.expectEqualSlices(u8, &expected, result);
}

test "can write OP_INDEX" {
    var image_buffer = ImageBuffer.init(std.testing.allocator);
    defer image_buffer.deinit();

    try image_buffer.opIndex(31);
    const result = image_buffer.asSlice();
    defer std.testing.allocator.free(result);

    const expected = [_]u8{ 0x1F };

    try std.testing.expectEqualSlices(u8, &expected, result);
}

test "can write OP_RGB" {
    var image_buffer = ImageBuffer.init(std.testing.allocator);
    defer image_buffer.deinit();

    const color = Color {
        .r = 12,
        .g = 102,
        .b = 74,
        .a = 255,
    };
    try image_buffer.opRgb(color);
    const result = image_buffer.asSlice();
    defer std.testing.allocator.free(result);

    const expected = [_]u8{ 0xFE, 0x0C, 0x66, 0x4A };

    try std.testing.expectEqualSlices(u8, &expected, result);
}

test "can write OP_RGBA" {
    var image_buffer = ImageBuffer.init(std.testing.allocator);
    defer image_buffer.deinit();

    const color = Color {
        .r = 12,
        .g = 102,
        .b = 74,
        .a = 16,
    };
    try image_buffer.opRgba(color);
    const result = image_buffer.asSlice();
    defer std.testing.allocator.free(result);

    const expected = [_]u8{ 0xFF, 0x0C, 0x66, 0x4A, 0x10 };

    try std.testing.expectEqualSlices(u8, &expected, result);
}

test "can write OP_DIFF" {
    var image_buffer = ImageBuffer.init(std.testing.allocator);
    defer image_buffer.deinit();

    try image_buffer.opDiff(-2, 1, 0);
    const result = image_buffer.asSlice();
    defer std.testing.allocator.free(result);

    const expected = [_]u8{ 0x4E };

    try std.testing.expectEqualSlices(u8, &expected, result);
}

test "can write OP_LUMA" {
    var image_buffer = ImageBuffer.init(std.testing.allocator);
    defer image_buffer.deinit();

    try image_buffer.opLuma(-28, -3, 6);
    const result = image_buffer.asSlice();
    defer std.testing.allocator.free(result);

    const expected = [_]u8{ 0x84, 0x5E };

    try std.testing.expectEqualSlices(u8, &expected, result);
}
