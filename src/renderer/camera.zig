const std = @import("std");
const math = @import("../math.zig");
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

pub const Camera = struct {
    pos: Vec4,
    yaw: f32, // radians, 0 = looking down -Z
    pitch: f32, // radians, clamped to avoid gimbal lock
    fov: f32, // vertical FOV in radians
    aspect: f32,
    near: f32,
    far: f32,

    pub fn init() Camera {
        return .{
            .pos = Vec4.init(0, 1.5, 5, 1),
            .yaw = 0,
            .pitch = 0,
            .fov = std.math.pi / 3.0, // 60 degrees
            .aspect = 1.0,
            .near = 0.1,
            .far = 100.0,
        };
    }

    pub fn forward(self: Camera) Vec4 {
        return Vec4.init(
            @sin(self.yaw) * @cos(self.pitch),
            @sin(self.pitch),
            -@cos(self.yaw) * @cos(self.pitch),
            0,
        );
    }

    pub fn right(self: Camera) Vec4 {
        return Vec4.init(@cos(self.yaw), 0, @sin(self.yaw), 0);
    }

    pub fn viewMatrix(self: Camera) Mat4 {
        const target = self.pos.add(self.forward());
        const up = Vec4.init(0, 1, 0, 0);
        return Mat4.lookAt(self.pos, target, up);
    }

    pub fn projectionMatrix(self: Camera) Mat4 {
        return Mat4.perspective(self.fov, self.aspect, self.near, self.far);
    }

    pub fn viewProjection(self: Camera) Mat4 {
        return self.projectionMatrix().mul(self.viewMatrix());
    }

    pub fn moveForward(self: *Camera, amount: f32) void {
        const fwd = self.forward().scale(amount);
        self.pos = self.pos.add(fwd);
    }

    pub fn moveRight(self: *Camera, amount: f32) void {
        const r = self.right().scale(amount);
        self.pos = self.pos.add(r);
    }

    pub fn rotate(self: *Camera, dyaw: f32, dpitch: f32) void {
        self.yaw += dyaw;
        self.pitch = std.math.clamp(self.pitch + dpitch, -std.math.pi / 2.0 + 0.01, std.math.pi / 2.0 - 0.01);
    }
};
