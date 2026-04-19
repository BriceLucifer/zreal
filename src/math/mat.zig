const Scalar = @import("scalar.zig").Scalar;
const Vec4 = @import("vec4.zig").Vec4;

const std = @import("std");
const expectApprox = std.testing.expectApproxEqAbs;

pub const Mat4 = struct {
    cols: [4]@Vector(4, f32),

    pub const identity = Mat4{
        .cols = .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        },
    };

    pub fn translation(x: f32, y: f32, z: f32) Mat4 {
        return .{
            .cols = .{
                .{ 1, 0, 0, 0 },
                .{ 0, 1, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ x, y, z, 1 },
            },
        };
    }

    pub fn scaling(x: f32, y: f32, z: f32) Mat4 {
        return .{
            .cols = .{
                .{ x, 0, 0, 0 },
                .{ 0, y, 0, 0 },
                .{ 0, 0, z, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    // 内部函数：直接操作 @Vector(4, f32)，mulVec4 和 mul 都复用它
    fn mulCol(self: Mat4, col: @Vector(4, f32)) @Vector(4, f32) {
        const V = @Vector(4, f32);
        var result = self.cols[0] * @as(V, @splat(col[0]));
        result = @mulAdd(V, self.cols[1], @as(V, @splat(col[1])), result);
        result = @mulAdd(V, self.cols[2], @as(V, @splat(col[2])), result);
        result = @mulAdd(V, self.cols[3], @as(V, @splat(col[3])), result);
        return result;
    }

    pub fn mulVec4(self: Mat4, v: Vec4) Vec4 {
        return .{ .data = self.mulCol(v.data) };
    }

    pub fn mul(self: Mat4, other: Mat4) Mat4 {
        return .{ .cols = .{
            self.mulCol(other.cols[0]),
            self.mulCol(other.cols[1]),
            self.mulCol(other.cols[2]),
            self.mulCol(other.cols[3]),
        } };
    }
};

test "mat4 identity mulVec4" {
    const v = Vec4.init(3, 4, 5, 1);
    const result = Mat4.identity.mulVec4(v);
    try expectApprox(result.x(), 3.0, 1e-6);
    try expectApprox(result.y(), 4.0, 1e-6);
    try expectApprox(result.z(), 5.0, 1e-6);
    try expectApprox(result.w(), 1.0, 1e-6);
}

test "mat4 translation" {
    const v = Vec4.init(0, 0, 0, 1);
    const result = Mat4.translation(5, 3, -2).mulVec4(v);
    try expectApprox(result.x(), 5.0, 1e-6);
    try expectApprox(result.y(), 3.0, 1e-6);
    try expectApprox(result.z(), -2.0, 1e-6);
}

test "mat4 scaling" {
    const v = Vec4.init(2, 3, 4, 1);
    const result = Mat4.scaling(2, 3, 0.5).mulVec4(v);
    try expectApprox(result.x(), 4.0, 1e-6);
    try expectApprox(result.y(), 9.0, 1e-6);
    try expectApprox(result.z(), 2.0, 1e-6);
}

test "mat4 mul: translation * scaling" {
    const model = Mat4.translation(10, 0, 0).mul(Mat4.scaling(2, 2, 2));
    const v = Vec4.init(1, 0, 0, 1);
    const result = model.mulVec4(v);
    // 先 scaling: (1,0,0) → (2,0,0), 再 translation: → (12,0,0)
    try expectApprox(result.x(), 12.0, 1e-6);
    try expectApprox(result.y(), 0.0, 1e-6);
    try expectApprox(result.z(), 0.0, 1e-6);
}

test "mat4 identity mul" {
    const t = Mat4.translation(1, 2, 3);
    const result = Mat4.identity.mul(t);
    const v = Vec4.init(0, 0, 0, 1);
    const r = result.mulVec4(v);
    try expectApprox(r.x(), 1.0, 1e-6);
    try expectApprox(r.y(), 2.0, 1e-6);
    try expectApprox(r.z(), 3.0, 1e-6);
}
