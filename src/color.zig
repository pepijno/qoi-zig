const std = @import("std");

pub const Color = struct {
    const Self = @This();
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn equals(self: *Self, color: Self) bool {
        return self.r == color.r
            and self.g == color.g
            and self.b == color.b
            and self.a == color.a;
    }

    pub fn hash(self: *Self) u6 {
        return @intCast(u6, (3 * @intCast(u32, self.r) + 5 * @intCast(u32, self.g) + 7 * @intCast(u32, self.b) + 11 * @intCast(u32, self.a)) % 64);
    }
};
