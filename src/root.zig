//! zreal engine - root module
const std = @import("std");
const Io = std.Io;

// Math
pub const Vec2 = @import("math/vec2.zig").Vec2;
pub const Vec3 = @import("math/vec3.zig").Vec3;
pub const Vec4 = @import("math/vec4.zig").Vec4;

pub fn printAnotherMessage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Run `zig build test` to run the tests.\n", .{});
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

// Pull in all tests from submodules
test {
    _ = @import("math/vec2.zig");
    _ = @import("math/vec3.zig");
    _ = @import("math/vec4.zig");
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
