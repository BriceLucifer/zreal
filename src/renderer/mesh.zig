const math = @import("../math.zig");
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Vertex = @import("framebuffer.zig").Vertex;

pub const Mesh = struct {
    vertices: []const Vertex,
    indices: []const [3]u32, // triangle indices

    pub fn drawWithMvp(
        self: Mesh,
        fb: anytype,
        mvp: anytype,
        light_dir: Vec3,
    ) void {
        for (self.indices) |tri| {
            fb.drawTriangle(
                self.vertices[tri[0]],
                self.vertices[tri[1]],
                self.vertices[tri[2]],
                mvp,
                light_dir,
            );
        }
    }
};

// ── Cube ──────────────────────────────────────────────────────────────

const cube_verts = [8]Vec4{
    Vec4.init(-0.5, -0.5, 0.5, 1), // 0: front-bottom-left
    Vec4.init(0.5, -0.5, 0.5, 1), // 1: front-bottom-right
    Vec4.init(0.5, 0.5, 0.5, 1), // 2: front-top-right
    Vec4.init(-0.5, 0.5, 0.5, 1), // 3: front-top-left
    Vec4.init(-0.5, -0.5, -0.5, 1), // 4: back-bottom-left
    Vec4.init(0.5, -0.5, -0.5, 1), // 5: back-bottom-right
    Vec4.init(0.5, 0.5, -0.5, 1), // 6: back-top-right
    Vec4.init(-0.5, 0.5, -0.5, 1), // 7: back-top-left
};

const cube_normals = [6]Vec3{
    Vec3.init(0, 0, 1), // front
    Vec3.init(0, 0, -1), // back
    Vec3.init(1, 0, 0), // right
    Vec3.init(-1, 0, 0), // left
    Vec3.init(0, 1, 0), // top
    Vec3.init(0, -1, 0), // bottom
};

// 6 faces × 4 vertices = 24 vertices (each face has its own normal)
fn makeCubeVertices(color: Vec3) [24]Vertex {
    const faces = [6][4]u32{
        .{ 0, 1, 2, 3 }, // front
        .{ 5, 4, 7, 6 }, // back
        .{ 1, 5, 6, 2 }, // right
        .{ 4, 0, 3, 7 }, // left
        .{ 3, 2, 6, 7 }, // top
        .{ 4, 5, 1, 0 }, // bottom
    };

    var verts: [24]Vertex = undefined;
    for (faces, 0..) |face, fi| {
        for (face, 0..) |vi, j| {
            verts[fi * 4 + j] = .{
                .pos = cube_verts[vi],
                .color = color,
                .normal = cube_normals[fi],
            };
        }
    }
    return verts;
}

fn makeCubeIndices() [12][3]u32 {
    var indices: [12][3]u32 = undefined;
    for (0..6) |fi| {
        const base: u32 = @intCast(fi * 4);
        indices[fi * 2] = .{ base, base + 1, base + 2 };
        indices[fi * 2 + 1] = .{ base, base + 2, base + 3 };
    }
    return indices;
}

const cube_vertices_default = makeCubeVertices(Vec3.init(0.8, 0.3, 0.2));
const cube_indices = makeCubeIndices();

pub fn createCube(color: Vec3) Mesh {
    const verts = comptime makeCubeVertices(color);
    return .{
        .vertices = &verts,
        .indices = &cube_indices,
    };
}

pub fn createCubeDefault() Mesh {
    return .{
        .vertices = &cube_vertices_default,
        .indices = &cube_indices,
    };
}

// ── Floor quad ────────────────────────────────────────────────────────

const floor_vertices = [4]Vertex{
    .{ .pos = Vec4.init(-10, 0, -10, 1), .color = Vec3.init(0.3, 0.5, 0.3), .normal = Vec3.init(0, 1, 0) },
    .{ .pos = Vec4.init(10, 0, -10, 1), .color = Vec3.init(0.3, 0.5, 0.3), .normal = Vec3.init(0, 1, 0) },
    .{ .pos = Vec4.init(10, 0, 10, 1), .color = Vec3.init(0.4, 0.6, 0.4), .normal = Vec3.init(0, 1, 0) },
    .{ .pos = Vec4.init(-10, 0, 10, 1), .color = Vec3.init(0.4, 0.6, 0.4), .normal = Vec3.init(0, 1, 0) },
};

const floor_indices = [2][3]u32{
    .{ 0, 1, 2 },
    .{ 0, 2, 3 },
};

pub fn createFloor() Mesh {
    return .{
        .vertices = &floor_vertices,
        .indices = &floor_indices,
    };
}
