const std = @import("std");
const math = @import("../math.zig");
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn fromVec3(v: Vec3) Color {
        return .{
            .r = @intFromFloat(std.math.clamp(v.x() * 255.0, 0.0, 255.0)),
            .g = @intFromFloat(std.math.clamp(v.y() * 255.0, 0.0, 255.0)),
            .b = @intFromFloat(std.math.clamp(v.z() * 255.0, 0.0, 255.0)),
        };
    }

    pub fn toVec3(self: Color) Vec3 {
        return Vec3.init(
            @as(f32, @floatFromInt(self.r)) / 255.0,
            @as(f32, @floatFromInt(self.g)) / 255.0,
            @as(f32, @floatFromInt(self.b)) / 255.0,
        );
    }
};

pub const Vertex = struct {
    pos: Vec4, // object-space position (w=1)
    color: Vec3, // vertex color (0..1)
    normal: Vec3, // vertex normal
};

pub const Framebuffer = struct {
    width: u32,
    height: u32,
    pixels: []Color,
    depth: []f32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Framebuffer {
        const size = @as(usize, width) * @as(usize, height);
        const pixels = try allocator.alloc(Color, size);
        const depth = try allocator.alloc(f32, size);
        var fb = Framebuffer{
            .width = width,
            .height = height,
            .pixels = pixels,
            .depth = depth,
            .allocator = allocator,
        };
        fb.clear(.{ .r = 0, .g = 0, .b = 0 });
        return fb;
    }

    pub fn deinit(self: *Framebuffer) void {
        self.allocator.free(self.pixels);
        self.allocator.free(self.depth);
    }

    pub fn clear(self: *Framebuffer, color: Color) void {
        @memset(self.pixels, color);
        @memset(self.depth, 1.0);
    }

    pub fn setPixel(self: *Framebuffer, px: u32, py: u32, z: f32, color: Color) void {
        if (px >= self.width or py >= self.height) return;
        const idx = @as(usize, py) * @as(usize, self.width) + @as(usize, px);
        // Depth test: smaller z = closer (after perspective divide, z is in [0,1] or [-1,1])
        if (z < self.depth[idx]) {
            self.depth[idx] = z;
            self.pixels[idx] = color;
        }
    }

    /// Draw a filled triangle with per-vertex colors and depth testing.
    pub fn drawTriangle(
        self: *Framebuffer,
        v0: Vertex,
        v1: Vertex,
        v2: Vertex,
        mvp: Mat4,
        light_dir: Vec3,
    ) void {
        const w_f: f32 = @floatFromInt(self.width);
        const h_f: f32 = @floatFromInt(self.height);

        // Transform to clip space
        const clip0 = mvp.mulVec4(v0.pos);
        const clip1 = mvp.mulVec4(v1.pos);
        const clip2 = mvp.mulVec4(v2.pos);

        // Perspective divide → NDC [-1,1]
        const cw0 = clip0.w();
        const cw1 = clip1.w();
        const cw2 = clip2.w();

        // Cull triangles behind camera (near plane)
        if (cw0 <= 0.001 or cw1 <= 0.001 or cw2 <= 0.001) return;

        const inv_w0 = 1.0 / cw0;
        const inv_w1 = 1.0 / cw1;
        const inv_w2 = 1.0 / cw2;

        const ndc0x = clip0.x() * inv_w0;
        const ndc0y = clip0.y() * inv_w0;
        const ndc0z = clip0.z() * inv_w0;
        const ndc1x = clip1.x() * inv_w1;
        const ndc1y = clip1.y() * inv_w1;
        const ndc1z = clip1.z() * inv_w1;
        const ndc2x = clip2.x() * inv_w2;
        const ndc2y = clip2.y() * inv_w2;
        const ndc2z = clip2.z() * inv_w2;

        // Trivial reject: all vertices outside same side of NDC cube
        if ((ndc0x < -1 and ndc1x < -1 and ndc2x < -1) or
            (ndc0x > 1 and ndc1x > 1 and ndc2x > 1) or
            (ndc0y < -1 and ndc1y < -1 and ndc2y < -1) or
            (ndc0y > 1 and ndc1y > 1 and ndc2y > 1)) return;

        // NDC → screen coords (Y flipped)
        const sx0 = (ndc0x + 1.0) * 0.5 * w_f;
        const sy0 = (1.0 - ndc0y) * 0.5 * h_f;
        const sx1 = (ndc1x + 1.0) * 0.5 * w_f;
        const sy1 = (1.0 - ndc1y) * 0.5 * h_f;
        const sx2 = (ndc2x + 1.0) * 0.5 * w_f;
        const sy2 = (1.0 - ndc2y) * 0.5 * h_f;

        // Bounding box — safe float→int with clamping
        const fmin_x = @max(0.0, @min(sx0, @min(sx1, sx2)));
        const fmax_x = @min(w_f - 1.0, @max(sx0, @max(sx1, sx2)));
        const fmin_y = @max(0.0, @min(sy0, @min(sy1, sy2)));
        const fmax_y = @min(h_f - 1.0, @max(sy0, @max(sy1, sy2)));

        if (fmin_x > fmax_x or fmin_y > fmax_y) return;
        if (fmax_x < 0 or fmax_y < 0) return;

        const min_x: u32 = @intFromFloat(@floor(fmin_x));
        const max_x: u32 = @min(self.width - 1, @as(u32, @intFromFloat(@ceil(fmax_x))));
        const min_y: u32 = @intFromFloat(@floor(fmin_y));
        const max_y: u32 = @min(self.height - 1, @as(u32, @intFromFloat(@ceil(fmax_y))));

        // Edge function area — use absolute value (no backface cull, depth buffer handles it)
        var area = edgeFn(sx0, sy0, sx1, sy1, sx2, sy2);
        if (area == 0) return; // degenerate
        const sign: f32 = if (area > 0) 1.0 else -1.0;
        area = @abs(area);
        const inv_area = 1.0 / area;

        // Simple directional lighting
        const face_normal = computeFaceNormal(v0, v1, v2);
        const ndotl = @abs(face_normal.dot(light_dir)); // abs: light both sides
        const ambient: f32 = 0.2;
        const light_factor = ambient + (1.0 - ambient) * ndotl;

        // Rasterize
        var py = min_y;
        while (py <= max_y) : (py += 1) {
            const pyf: f32 = @as(f32, @floatFromInt(py)) + 0.5;
            var px = min_x;
            while (px <= max_x) : (px += 1) {
                const pxf: f32 = @as(f32, @floatFromInt(px)) + 0.5;

                // Barycentric coords (with sign correction for winding)
                const w_a = edgeFn(sx1, sy1, sx2, sy2, pxf, pyf) * inv_area * sign;
                const w_b = edgeFn(sx2, sy2, sx0, sy0, pxf, pyf) * inv_area * sign;
                const w_c = 1.0 - w_a - w_b;

                if (w_a >= 0 and w_b >= 0 and w_c >= 0) {
                    const z = w_a * ndc0z + w_b * ndc1z + w_c * ndc2z;

                    // Interpolate color + apply lighting
                    const col = v0.color.scale(w_a).add(v1.color.scale(w_b)).add(v2.color.scale(w_c));
                    const lit = col.scale(light_factor);

                    self.setPixel(px, py, z, Color.fromVec3(lit));
                }
            }
        }
    }
};

fn edgeFn(ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32) f32 {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

fn computeFaceNormal(v0: Vertex, v1: Vertex, v2: Vertex) Vec3 {
    const p0 = Vec3.init(v0.pos.x(), v0.pos.y(), v0.pos.z());
    const p1 = Vec3.init(v1.pos.x(), v1.pos.y(), v1.pos.z());
    const p2 = Vec3.init(v2.pos.x(), v2.pos.y(), v2.pos.z());
    const e1 = p1.sub(p0);
    const e2 = p2.sub(p0);
    const n = e1.cross(e2);
    const len = n.length();
    if (len < 1e-8) return Vec3.init(0, 1, 0);
    return n.scale(1.0 / len);
}

test "framebuffer init and clear" {
    const fb = try Framebuffer.init(std.testing.allocator, 8, 8);
    defer {
        var fb_mut = fb;
        fb_mut.deinit();
    }
    try std.testing.expect(fb.pixels.len == 64);
    try std.testing.expect(fb.depth.len == 64);
    try std.testing.expect(fb.pixels[0].r == 0);
    try std.testing.expect(fb.depth[0] == 1.0);
}

test "framebuffer setPixel with depth" {
    var fb = try Framebuffer.init(std.testing.allocator, 4, 4);
    defer fb.deinit();

    fb.setPixel(1, 1, 0.5, .{ .r = 255, .g = 0, .b = 0 });
    try std.testing.expect(fb.pixels[5].r == 255);

    // Closer pixel should overwrite
    fb.setPixel(1, 1, 0.3, .{ .r = 0, .g = 255, .b = 0 });
    try std.testing.expect(fb.pixels[5].g == 255);
    try std.testing.expect(fb.pixels[5].r == 0);

    // Farther pixel should NOT overwrite
    fb.setPixel(1, 1, 0.9, .{ .r = 0, .g = 0, .b = 255 });
    try std.testing.expect(fb.pixels[5].g == 255);
    try std.testing.expect(fb.pixels[5].b == 0);
}
