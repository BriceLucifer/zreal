pub const Scalar = @import("scalar.zig").Scalar;

const std = @import("std");
const expectApprox = std.testing.expectApproxEqAbs;

pub const Vec4 = struct {
    data: @Vector(4, f32),

    pub fn init(vx: f32, vy: f32, vz: f32, vw: f32) Vec4 {
        return .{ .data = .{ vx, vy, vz, vw } };
    }

    pub fn x(self: Vec4) Scalar {
        return self.data[0];
    }

    pub fn y(self: Vec4) Scalar {
        return self.data[1];
    }

    pub fn z(self: Vec4) Scalar {
        return self.data[2];
    }

    pub fn w(self: Vec4) Scalar {
        return self.data[3];
    }

    pub fn add(self: Vec4, other: Vec4) Vec4 {
        return .{ .data = self.data + other.data };
    }

    pub fn sub(self: Vec4, other: Vec4) Vec4 {
        return .{ .data = self.data - other.data };
    }

    pub fn scale(self: Vec4, scalar: Scalar) Vec4 {
        return .{ .data = self.data * @as(@Vector(4, f32), @splat(scalar)) };
    }

    pub fn dot(self: Vec4, other: Vec4) Scalar {
        return @reduce(.Add, self.data * other.data);
    }

    pub fn length(self: Vec4) Scalar {
        return @sqrt(self.dot(self));
    }

    pub fn normalize(self: Vec4) Vec4 {
        return self.scale(1.0 / self.length());
    }

    pub fn negate(self: Vec4) Vec4 {
        return .{ .data = -self.data };
    }

    /// Linear interpolation: self + (other - self) * t
    pub fn lerp(self: Vec4, other: Vec4, t: Scalar) Vec4 {
        return self.add(other.sub(self).scale(t));
    }

    /// Element-wise multiply
    pub fn mul(self: Vec4, other: Vec4) Vec4 {
        return .{ .data = self.data * other.data };
    }

    /// Element-wise min
    pub fn min(self: Vec4, other: Vec4) Vec4 {
        return .{ .data = @min(self.data, other.data) };
    }

    /// Element-wise max
    pub fn max(self: Vec4, other: Vec4) Vec4 {
        return .{ .data = @max(self.data, other.data) };
    }
};

test "vec4 init and accessors" {
    const v = Vec4.init(1, 2, 3, 4);
    try expectApprox(v.x(), 1.0, 1e-6);
    try expectApprox(v.y(), 2.0, 1e-6);
    try expectApprox(v.z(), 3.0, 1e-6);
    try expectApprox(v.w(), 4.0, 1e-6);
}

test "vec4 add and sub" {
    const a = Vec4.init(1, 2, 3, 4);
    const b = Vec4.init(5, 6, 7, 8);

    const sum = a.add(b);
    try expectApprox(sum.x(), 6.0, 1e-6);
    try expectApprox(sum.y(), 8.0, 1e-6);
    try expectApprox(sum.z(), 10.0, 1e-6);
    try expectApprox(sum.w(), 12.0, 1e-6);

    const diff = a.sub(b);
    try expectApprox(diff.x(), -4.0, 1e-6);
    try expectApprox(diff.w(), -4.0, 1e-6);
}

test "vec4 scale" {
    const v = Vec4.init(1, 2, 3, 4);
    const scaled = v.scale(0.5);
    try expectApprox(scaled.x(), 0.5, 1e-6);
    try expectApprox(scaled.w(), 2.0, 1e-6);
}

test "vec4 dot" {
    const a = Vec4.init(1, 2, 3, 4);
    const b = Vec4.init(1, 2, 3, 4);
    try expectApprox(a.dot(b), 30.0, 1e-6); // 1+4+9+16
}

test "vec4 length and normalize" {
    const v = Vec4.init(1, 0, 0, 0);
    try expectApprox(v.length(), 1.0, 1e-6);

    const v2 = Vec4.init(0, 0, 3, 4);
    try expectApprox(v2.length(), 5.0, 1e-6);

    const n = v2.normalize();
    try expectApprox(n.length(), 1.0, 1e-6);
}

test "vec4 lerp" {
    const a = Vec4.init(0, 0, 0, 0);
    const b = Vec4.init(10, 20, 30, 40);

    const quarter = a.lerp(b, 0.25);
    try expectApprox(quarter.x(), 2.5, 1e-6);
    try expectApprox(quarter.w(), 10.0, 1e-6);
}

test "vec4 element-wise min max" {
    const a = Vec4.init(1, 5, 3, 7);
    const b = Vec4.init(4, 2, 6, 1);

    const lo = a.min(b);
    try expectApprox(lo.x(), 1.0, 1e-6);
    try expectApprox(lo.y(), 2.0, 1e-6);

    const hi = a.max(b);
    try expectApprox(hi.x(), 4.0, 1e-6);
    try expectApprox(hi.y(), 5.0, 1e-6);
}
