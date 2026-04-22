const Scalar = @import("scalar.zig").Scalar;
const Mat4 = @import("mat.zig").Mat4;

const std = @import("std");
const expectApprox = std.testing.expectApproxEqAbs;

pub const Quat = struct {
    // Stored as @Vector(4, f32): x, y, z, w
    data: @Vector(4, f32),

    pub fn init(vx: f32, vy: f32, vz: f32, vw: f32) Quat {
        return .{ .data = .{ vx, vy, vz, vw } };
    }

    pub const identity = Quat{ .data = .{ 0, 0, 0, 1 } };

    pub fn x(self: Quat) Scalar {
        return self.data[0];
    }
    pub fn y(self: Quat) Scalar {
        return self.data[1];
    }
    pub fn z(self: Quat) Scalar {
        return self.data[2];
    }
    pub fn w(self: Quat) Scalar {
        return self.data[3];
    }

    pub fn fromAxisAngle(axis_x: f32, axis_y: f32, axis_z: f32, angle: f32) Quat {
        const half = angle * 0.5;
        const s = @sin(half);
        const c = @cos(half);
        // Normalize axis
        const ax: @Vector(4, f32) = .{ axis_x, axis_y, axis_z, 0 };
        const len = @sqrt(@reduce(.Add, ax * ax));
        const n = ax / @as(@Vector(4, f32), @splat(len));
        return .{ .data = .{ n[0] * s, n[1] * s, n[2] * s, c } };
    }

    pub fn mul(self: Quat, other: Quat) Quat {
        const a = self.data;
        const b = other.data;
        return .{ .data = .{
            a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
            a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
            a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
            a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
        } };
    }

    pub fn conjugate(self: Quat) Quat {
        return .{ .data = .{ -self.data[0], -self.data[1], -self.data[2], self.data[3] } };
    }

    pub fn length(self: Quat) Scalar {
        return @sqrt(@reduce(.Add, self.data * self.data));
    }

    pub fn normalize(self: Quat) Quat {
        const len = self.length();
        return .{ .data = self.data / @as(@Vector(4, f32), @splat(len)) };
    }

    pub fn toMat4(self: Quat) Mat4 {
        const q = self.data;
        const xx = q[0] * q[0];
        const yy = q[1] * q[1];
        const zz = q[2] * q[2];
        const xy = q[0] * q[1];
        const xz = q[0] * q[2];
        const yz = q[1] * q[2];
        const wx = q[3] * q[0];
        const wy = q[3] * q[1];
        const wz = q[3] * q[2];

        return .{ .cols = .{
            .{ 1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0 },
            .{ 2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0 },
            .{ 2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0 },
            .{ 0, 0, 0, 1 },
        } };
    }

    pub fn slerp(self: Quat, other: Quat, t: f32) Quat {
        var dot: f32 = @reduce(.Add, self.data * other.data);
        var b = other.data;

        // If dot < 0, negate one to take the short path
        if (dot < 0) {
            b = -b;
            dot = -dot;
        }

        // If very close, lerp to avoid division by zero
        if (dot > 0.9995) {
            const result = self.data + (b - self.data) * @as(@Vector(4, f32), @splat(t));
            const len = @sqrt(@reduce(.Add, result * result));
            return .{ .data = result / @as(@Vector(4, f32), @splat(len)) };
        }

        const theta = std.math.acos(dot);
        const sin_theta = @sin(theta);
        const w1 = @sin((1 - t) * theta) / sin_theta;
        const w2 = @sin(t * theta) / sin_theta;

        return .{
            .data = self.data * @as(@Vector(4, f32), @splat(w1)) + b * @as(@Vector(4, f32), @splat(w2)),
        };
    }
};

test "quat identity" {
    const q = Quat.identity;
    try expectApprox(q.w(), 1.0, 1e-6);
    try expectApprox(q.length(), 1.0, 1e-6);
}

test "quat fromAxisAngle round-trip" {
    const q = Quat.fromAxisAngle(0, 1, 0, std.math.pi / 2.0);
    try expectApprox(q.length(), 1.0, 1e-5);

    // Convert to Mat4 and transform (1,0,0) — should give ~(0,0,-1)
    const m = q.toMat4();
    const Vec4 = @import("vec4.zig").Vec4;
    const v = Vec4.init(1, 0, 0, 1);
    const result = m.mulVec4(v);
    try expectApprox(result.x(), 0.0, 1e-5);
    try expectApprox(result.z(), -1.0, 1e-5);
}

test "quat mul associativity" {
    const a = Quat.fromAxisAngle(1, 0, 0, 0.5);
    const b = Quat.fromAxisAngle(0, 1, 0, 0.7);
    const c = Quat.fromAxisAngle(0, 0, 1, 0.3);

    const ab_c = a.mul(b).mul(c);
    const a_bc = a.mul(b.mul(c));

    try expectApprox(ab_c.x(), a_bc.x(), 1e-5);
    try expectApprox(ab_c.y(), a_bc.y(), 1e-5);
    try expectApprox(ab_c.z(), a_bc.z(), 1e-5);
    try expectApprox(ab_c.w(), a_bc.w(), 1e-5);
}

test "quat conjugate" {
    const q = Quat.fromAxisAngle(0, 1, 0, 1.0);
    const qc = q.conjugate();
    const result = q.mul(qc);
    // q * conjugate(q) = identity (for unit quaternion)
    try expectApprox(result.x(), 0.0, 1e-5);
    try expectApprox(result.y(), 0.0, 1e-5);
    try expectApprox(result.z(), 0.0, 1e-5);
    try expectApprox(result.w(), 1.0, 1e-5);
}

test "quat slerp endpoints" {
    const a = Quat.fromAxisAngle(0, 1, 0, 0.0);
    const b = Quat.fromAxisAngle(0, 1, 0, std.math.pi);

    const start = a.slerp(b, 0.0);
    try expectApprox(start.x(), a.x(), 1e-5);
    try expectApprox(start.w(), a.w(), 1e-5);

    const end = a.slerp(b, 1.0);
    try expectApprox(end.x(), b.x(), 1e-5);
    try expectApprox(end.w(), b.w(), 1e-5);
}
