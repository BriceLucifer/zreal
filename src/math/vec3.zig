pub const Scalar = @import("scalar.zig").Scalar;

const std = @import("std");
const expectApprox = std.testing.expectApproxEqAbs;

pub const Vec3 = struct {
    // Stored as 4-wide SIMD, w always 0. Fills a full 128-bit register.
    data: @Vector(4, f32),

    pub fn init(vx: f32, vy: f32, vz: f32) Vec3 {
        return .{ .data = .{ vx, vy, vz, 0 } };
    }

    pub fn x(self: Vec3) Scalar {
        return self.data[0];
    }

    pub fn y(self: Vec3) Scalar {
        return self.data[1];
    }

    pub fn z(self: Vec3) Scalar {
        return self.data[2];
    }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return .{ .data = self.data + other.data };
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return .{ .data = self.data - other.data };
    }

    pub fn scale(self: Vec3, scalar: Scalar) Vec3 {
        return .{ .data = self.data * @as(@Vector(4, f32), @splat(scalar)) };
    }

    pub fn dot(self: Vec3, other: Vec3) Scalar {
        // Only sum x, y, z — w is 0 so it doesn't affect the result
        return @reduce(.Add, self.data * other.data);
    }

    pub fn length(self: Vec3) Scalar {
        return @sqrt(self.dot(self));
    }

    pub fn normalize(self: Vec3) Vec3 {
        return self.scale(1.0 / self.length());
    }

    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        // a × b = (a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x)
        const a_yzx = @shuffle(f32, self.data, undefined, [4]i32{ 1, 2, 0, 3 });
        const a_zxy = @shuffle(f32, self.data, undefined, [4]i32{ 2, 0, 1, 3 });
        const b_yzx = @shuffle(f32, other.data, undefined, [4]i32{ 1, 2, 0, 3 });
        const b_zxy = @shuffle(f32, other.data, undefined, [4]i32{ 2, 0, 1, 3 });
        const result = a_yzx * b_zxy - a_zxy * b_yzx;
        return .{ .data = .{ result[0], result[1], result[2], 0 } };
    }

    pub fn negate(self: Vec3) Vec3 {
        return .{ .data = -self.data };
    }

    /// Linear interpolation: self + (other - self) * t
    pub fn lerp(self: Vec3, other: Vec3, t: Scalar) Vec3 {
        return self.add(other.sub(self).scale(t));
    }
};

test "vec3 init and accessors" {
    const v = Vec3.init(1, 2, 3);
    try expectApprox(v.x(), 1.0, 1e-6);
    try expectApprox(v.y(), 2.0, 1e-6);
    try expectApprox(v.z(), 3.0, 1e-6);
}

test "vec3 add and sub" {
    const a = Vec3.init(1, 2, 3);
    const b = Vec3.init(4, 5, 6);

    const sum = a.add(b);
    try expectApprox(sum.x(), 5.0, 1e-6);
    try expectApprox(sum.y(), 7.0, 1e-6);
    try expectApprox(sum.z(), 9.0, 1e-6);

    const diff = a.sub(b);
    try expectApprox(diff.x(), -3.0, 1e-6);
    try expectApprox(diff.y(), -3.0, 1e-6);
    try expectApprox(diff.z(), -3.0, 1e-6);
}

test "vec3 scale" {
    const v = Vec3.init(2, 3, 4);
    const scaled = v.scale(2.0);
    try expectApprox(scaled.x(), 4.0, 1e-6);
    try expectApprox(scaled.y(), 6.0, 1e-6);
    try expectApprox(scaled.z(), 8.0, 1e-6);
}

test "vec3 dot" {
    const a = Vec3.init(1, 0, 0);
    const b = Vec3.init(0, 1, 0);
    try expectApprox(a.dot(b), 0.0, 1e-6); // perpendicular

    const c = Vec3.init(1, 2, 3);
    try expectApprox(c.dot(c), 14.0, 1e-6); // 1 + 4 + 9
}

test "vec3 length and normalize" {
    const v = Vec3.init(0, 3, 4);
    try expectApprox(v.length(), 5.0, 1e-6);

    const n = v.normalize();
    try expectApprox(n.length(), 1.0, 1e-6);
}

test "vec3 cross" {
    const right = Vec3.init(1, 0, 0);
    const up = Vec3.init(0, 1, 0);
    const forward = right.cross(up); // right × up = forward (0,0,1)

    try expectApprox(forward.x(), 0.0, 1e-6);
    try expectApprox(forward.y(), 0.0, 1e-6);
    try expectApprox(forward.z(), 1.0, 1e-6);

    // Anti-commutativity: a × b = -(b × a)
    const backward = up.cross(right);
    try expectApprox(backward.z(), -1.0, 1e-6);
}

test "vec3 lerp" {
    const a = Vec3.init(0, 0, 0);
    const b = Vec3.init(10, 20, 30);

    const mid = a.lerp(b, 0.5);
    try expectApprox(mid.x(), 5.0, 1e-6);
    try expectApprox(mid.y(), 10.0, 1e-6);
    try expectApprox(mid.z(), 15.0, 1e-6);
}
