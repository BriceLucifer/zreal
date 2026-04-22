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

    pub fn rotationX(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{ .cols = .{
            .{ 1, 0, 0, 0 },
            .{ 0, c, s, 0 },
            .{ 0, -s, c, 0 },
            .{ 0, 0, 0, 1 },
        } };
    }

    pub fn rotationY(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{ .cols = .{
            .{ c, 0, -s, 0 },
            .{ 0, 1, 0, 0 },
            .{ s, 0, c, 0 },
            .{ 0, 0, 0, 1 },
        } };
    }

    pub fn rotationZ(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{ .cols = .{
            .{ c, s, 0, 0 },
            .{ -s, c, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        } };
    }

    pub fn transpose(self: Mat4) Mat4 {
        // Transpose using SIMD shuffles
        const c = self.cols;
        return .{ .cols = .{
            .{ c[0][0], c[1][0], c[2][0], c[3][0] },
            .{ c[0][1], c[1][1], c[2][1], c[3][1] },
            .{ c[0][2], c[1][2], c[2][2], c[3][2] },
            .{ c[0][3], c[1][3], c[2][3], c[3][3] },
        } };
    }

    pub fn lookAt(eye: Vec4, target: Vec4, world_up: Vec4) Mat4 {
        const V = @Vector(4, f32);
        // forward = normalize(eye - target)
        const f_raw = eye.data - target.data;
        const f_len = @sqrt(@reduce(.Add, f_raw * f_raw));
        const f = f_raw / @as(V, @splat(f_len));

        // right = normalize(cross(world_up, forward))
        // cross(a, b) = (a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x)
        const u = world_up.data;
        const r_raw = V{
            u[1] * f[2] - u[2] * f[1],
            u[2] * f[0] - u[0] * f[2],
            u[0] * f[1] - u[1] * f[0],
            0,
        };
        const r_len = @sqrt(@reduce(.Add, r_raw * r_raw));
        const r = r_raw / @as(V, @splat(r_len));

        // up = cross(forward, right)
        const up = V{
            f[1] * r[2] - f[2] * r[1],
            f[2] * r[0] - f[0] * r[2],
            f[0] * r[1] - f[1] * r[0],
            0,
        };

        const e = eye.data;
        return .{ .cols = .{
            .{ r[0], up[0], f[0], 0 },
            .{ r[1], up[1], f[1], 0 },
            .{ r[2], up[2], f[2], 0 },
            .{ -@reduce(.Add, r * e), -@reduce(.Add, up * e), -@reduce(.Add, f * e), 1 },
        } };
    }

    pub fn perspective(fov_y: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const tan_half = @tan(fov_y / 2.0);
        const f = 1.0 / tan_half;
        const range_inv = 1.0 / (near - far);
        return .{ .cols = .{
            .{ f / aspect, 0, 0, 0 },
            .{ 0, f, 0, 0 },
            .{ 0, 0, (far + near) * range_inv, -1 },
            .{ 0, 0, 2.0 * far * near * range_inv, 0 },
        } };
    }

    /// Access element at row, col
    pub fn at(self: Mat4, row: usize, col: usize) f32 {
        return self.cols[col][row];
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

test "mat4 rotationY 90 degrees" {
    const angle = std.math.pi / 2.0;
    const r = Mat4.rotationY(angle);
    // Rotating (1,0,0) by 90° around Y gives (0,0,-1) in right-handed coords
    const v = Vec4.init(1, 0, 0, 1);
    const result = r.mulVec4(v);
    try expectApprox(result.x(), 0.0, 1e-5);
    try expectApprox(result.y(), 0.0, 1e-5);
    try expectApprox(result.z(), -1.0, 1e-5);
}

test "mat4 transpose" {
    const t = Mat4.translation(1, 2, 3);
    const tt = t.transpose().transpose();
    const v = Vec4.init(0, 0, 0, 1);
    const r = tt.mulVec4(v);
    try expectApprox(r.x(), 1.0, 1e-6);
    try expectApprox(r.y(), 2.0, 1e-6);
    try expectApprox(r.z(), 3.0, 1e-6);
}

test "mat4 perspective basic" {
    const p = Mat4.perspective(std.math.pi / 4.0, 1.0, 0.1, 100.0);
    // A point at the center should map to 0,0
    const v = Vec4.init(0, 0, -1, 1);
    const result = p.mulVec4(v);
    try expectApprox(result.x(), 0.0, 1e-5);
    try expectApprox(result.y(), 0.0, 1e-5);
    // w should be positive (in front of camera)
    try std.testing.expect(result.w() > 0);
}

test "mat4 lookAt" {
    const eye = Vec4.init(0, 0, 5, 1);
    const target = Vec4.init(0, 0, 0, 1);
    const up = Vec4.init(0, 1, 0, 0);
    const view = Mat4.lookAt(eye, target, up);

    // Origin should map to (0, 0, -5) in view space (in front of camera)
    const result = view.mulVec4(Vec4.init(0, 0, 0, 1));
    try expectApprox(result.x(), 0.0, 1e-5);
    try expectApprox(result.y(), 0.0, 1e-5);
    // z should be negative (OpenGL convention: camera looks down -Z)
    try std.testing.expect(result.z() < 0);
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
