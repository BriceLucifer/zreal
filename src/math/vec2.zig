pub const Scalar = @import("scalar.zig").Scalar;

const std = @import("std");
const expect = std.testing.expect;
const expectApprox = std.testing.expectApproxEqAbs;

pub const Vec2 = struct {
    data: @Vector(2, f32),

    pub fn init(array: [2]f32) Vec2 {
        return .{ .data = array };
    }

    pub fn x(self: Vec2) Scalar {
        return self.data[0];
    }

    pub fn y(self: Vec2) Scalar {
        return self.data[1];
    }

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return .{ .data = self.data + other.data };
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return .{ .data = self.data - other.data };
    }

    pub fn scale(self: Vec2, scalar: Scalar) Vec2 {
        return .{ .data = self.data * @as(@Vector(2, f32), @splat(scalar)) };
    }

    pub fn dot(self: Vec2, other: Vec2) Scalar {
        return @reduce(.Add, self.data * other.data);
    }

    pub fn length(self: Vec2) Scalar {
        return @sqrt(self.dot(self));
    }

    pub fn normalize(self: Vec2) Vec2 {
        return self.scale(1.0 / self.length());
    }

    /// 2D pseudo cross product: returns signed area of parallelogram
    /// > 0: other is to the left (counter-clockwise)
    /// < 0: other is to the right (clockwise)
    /// = 0: parallel
    pub fn cross(self: Vec2, other: Vec2) Scalar {
        return self.x() * other.y() - self.y() * other.x();
    }
};

test "vec2 init and accessors" {
    const v = Vec2.init(.{ 3, 4 });
    try expectApprox(v.x(), 3.0, 1e-6);
    try expectApprox(v.y(), 4.0, 1e-6);
}

test "vec2 add and sub" {
    const a = Vec2.init(.{ 1, 2 });
    const b = Vec2.init(.{ 3, 4 });

    const sum = a.add(b);
    try expectApprox(sum.x(), 4.0, 1e-6);
    try expectApprox(sum.y(), 6.0, 1e-6);

    const diff = a.sub(b);
    try expectApprox(diff.x(), -2.0, 1e-6);
    try expectApprox(diff.y(), -2.0, 1e-6);
}

test "vec2 scale" {
    const v = Vec2.init(.{ 2, 3 });
    const scaled = v.scale(3.0);
    try expectApprox(scaled.x(), 6.0, 1e-6);
    try expectApprox(scaled.y(), 9.0, 1e-6);
}

test "vec2 dot" {
    const a = Vec2.init(.{ 1, 0 });
    const b = Vec2.init(.{ 0, 1 });
    try expectApprox(a.dot(b), 0.0, 1e-6); // perpendicular

    const c = Vec2.init(.{ 3, 4 });
    try expectApprox(c.dot(c), 25.0, 1e-6); // 9 + 16
}

test "vec2 length and normalize" {
    const v = Vec2.init(.{ 3, 4 });
    try expectApprox(v.length(), 5.0, 1e-6);

    const n = v.normalize();
    try expectApprox(n.length(), 1.0, 1e-6);
    try expectApprox(n.x(), 0.6, 1e-6);
    try expectApprox(n.y(), 0.8, 1e-6);
}

test "vec2 cross" {
    const a = Vec2.init(.{ 1, 0 });
    const b = Vec2.init(.{ 0, 1 });
    try expectApprox(a.cross(b), 1.0, 1e-6);  // counter-clockwise
    try expectApprox(b.cross(a), -1.0, 1e-6); // clockwise
}
