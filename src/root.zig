//! zreal engine - root module
const std = @import("std");

// Math
pub const Vec2 = @import("math/vec2.zig").Vec2;
pub const Vec3 = @import("math/vec3.zig").Vec3;
pub const Vec4 = @import("math/vec4.zig").Vec4;
pub const Mat4 = @import("math/mat.zig").Mat4;
pub const Quat = @import("math/quat.zig").Quat;
pub const Scalar = @import("math/scalar.zig").Scalar;

// Renderer
pub const Framebuffer = @import("renderer/framebuffer.zig").Framebuffer;
pub const Color = @import("renderer/framebuffer.zig").Color;
pub const Vertex = @import("renderer/framebuffer.zig").Vertex;
pub const Camera = @import("renderer/camera.zig").Camera;
pub const mesh = @import("renderer/mesh.zig");
pub const Mesh = mesh.Mesh;
pub const terminal = @import("renderer/terminal.zig");

// Pull in all tests from submodules
test {
    _ = @import("math/vec2.zig");
    _ = @import("math/vec3.zig");
    _ = @import("math/vec4.zig");
    _ = @import("math/mat.zig");
    _ = @import("math/quat.zig");
    _ = @import("renderer/framebuffer.zig");
}
