const std = @import("std");
const zreal = @import("zreal");
const Vec3 = zreal.Vec3;
const Vec4 = zreal.Vec4;
const Mat4 = zreal.Mat4;
const Framebuffer = zreal.Framebuffer;
const Camera = zreal.Camera;
const m = zreal.mesh;
const terminal = zreal.terminal;

// ── Config ────────────────────────────────────────────────────────────

const FB_WIDTH = 120;
const FB_HEIGHT = 80; // terminal rows = 40 (half-block trick)
const MAX_CUBES = 20;
const MOVE_SPEED: f32 = 4.0;
const ROTATE_SPEED: f32 = 2.0;
const ARENA_SIZE: f32 = 8.0;
const TARGET_FPS = 30;
const FRAME_NS: u64 = std.time.ns_per_s / TARGET_FPS;

// ── Game State ────────────────��───────────────────────────────────────

const CubeEntity = struct {
    pos: Vec4,
    vel: Vec3,
    color: Vec3,
    alive: bool,
};

const GameState = struct {
    camera: Camera,
    cubes: [MAX_CUBES]CubeEntity,
    cube_count: u32,
    score: u32,
    time: f32,
    spawn_timer: f32,
    running: bool,
};

fn initGame() GameState {
    var state = GameState{
        .camera = Camera.init(),
        .cubes = undefined,
        .cube_count = 0,
        .score = 0,
        .time = 0,
        .spawn_timer = 0,
        .running = true,
    };
    state.camera.pos = Vec4.init(0, 1.5, 5, 1);
    state.camera.aspect = @as(f32, FB_WIDTH) / @as(f32, FB_HEIGHT);

    for (&state.cubes) |*c| {
        c.alive = false;
    }
    spawnCube(&state);
    spawnCube(&state);
    spawnCube(&state);

    return state;
}

fn spawnCube(state: *GameState) void {
    for (&state.cubes) |*c| {
        if (!c.alive) {
            const seed = state.time * 1000.0 + @as(f32, @floatFromInt(state.cube_count)) * 137.0;
            const hash = @as(u32, @intFromFloat(@mod(@abs(seed * 2654435.761), 65536.0)));

            const fx = @as(f32, @floatFromInt(hash % 100)) / 100.0;
            const fz = @as(f32, @floatFromInt((hash / 100) % 100)) / 100.0;
            const fc = @as(f32, @floatFromInt((hash / 10000) % 100)) / 100.0;

            c.* = .{
                .pos = Vec4.init(
                    (fx - 0.5) * ARENA_SIZE * 1.5,
                    0.5,
                    (fz - 0.5) * ARENA_SIZE * 1.5,
                    1,
                ),
                .vel = Vec3.init((fx - 0.5) * 2, 0, (fz - 0.5) * 2),
                .color = Vec3.init(0.3 + fc * 0.7, 0.3 + (1.0 - fc) * 0.5, 0.2 + fx * 0.6),
                .alive = true,
            };
            state.cube_count += 1;
            return;
        }
    }
}

// ── Input ────────────���────────────────────────────────────────────────

const Input = struct {
    forward: bool = false,
    backward: bool = false,
    left: bool = false,
    right: bool = false,
    turn_left: bool = false,
    turn_right: bool = false,
    quit: bool = false,
};

fn readInput(tty: std.posix.fd_t) Input {
    var input = Input{};
    var buf: [32]u8 = undefined;

    while (true) {
        const n = std.posix.read(tty, &buf) catch break;
        if (n == 0) break;
        for (buf[0..n]) |ch| {
            switch (ch) {
                'w', 'W' => input.forward = true,
                's', 'S' => input.backward = true,
                'a', 'A' => input.left = true,
                'd', 'D' => input.right = true,
                'q', 'Q' => input.turn_left = true,
                'e', 'E' => input.turn_right = true,
                27, 'x', 'X' => input.quit = true,
                else => {},
            }
        }
    }
    return input;
}

// ── Physics ─────────────────────────────────────────��─────────────────

fn updatePhysics(state: *GameState, dt: f32) void {
    for (&state.cubes) |*c| {
        if (!c.alive) continue;

        const new_x = c.pos.x() + c.vel.x() * dt;
        const new_z = c.pos.z() + c.vel.z() * dt;

        var vx = c.vel.x();
        var vz = c.vel.z();
        if (new_x < -ARENA_SIZE or new_x > ARENA_SIZE) vx = -vx;
        if (new_z < -ARENA_SIZE or new_z > ARENA_SIZE) vz = -vz;
        c.vel = Vec3.init(vx, 0, vz);

        c.pos = Vec4.init(
            std.math.clamp(new_x, -ARENA_SIZE, ARENA_SIZE),
            c.pos.y(),
            std.math.clamp(new_z, -ARENA_SIZE, ARENA_SIZE),
            1,
        );
    }

    // Player-cube AABB collision
    const px = state.camera.pos.x();
    const pz = state.camera.pos.z();
    for (&state.cubes) |*c| {
        if (!c.alive) continue;
        if (@abs(px - c.pos.x()) < 0.8 and @abs(pz - c.pos.z()) < 0.8) {
            c.alive = false;
            state.score += 1;
        }
    }
}

// ── Rendering ─────────────────────────────────────────────────────────

const cube_colors = [_]Vec3{
    Vec3.init(0.9, 0.2, 0.2),
    Vec3.init(0.2, 0.7, 0.9),
    Vec3.init(0.9, 0.8, 0.2),
    Vec3.init(0.3, 0.9, 0.3),
    Vec3.init(0.9, 0.4, 0.8),
    Vec3.init(0.6, 0.4, 0.9),
};

fn renderFrame(fb: *Framebuffer, state: *const GameState) void {
    fb.clear(.{ .r = 20, .g = 25, .b = 40 });

    const vp = state.camera.viewProjection();
    const light_dir = Vec3.init(0.5, 0.8, 0.3).normalize();

    // Floor
    const floor = m.createFloor();
    floor.drawWithMvp(fb, vp, light_dir);

    // Walls
    drawWall(fb, vp, light_dir, -ARENA_SIZE, 0, true);
    drawWall(fb, vp, light_dir, ARENA_SIZE, 0, true);
    drawWall(fb, vp, light_dir, 0, -ARENA_SIZE, false);
    drawWall(fb, vp, light_dir, 0, ARENA_SIZE, false);

    // Cubes
    for (state.cubes, 0..) |c, i| {
        if (!c.alive) continue;
        const color = cube_colors[i % cube_colors.len];
        const model = Mat4.translation(c.pos.x(), c.pos.y(), c.pos.z());
        const mvp = vp.mul(model);
        drawColoredCube(fb, mvp, light_dir, color);
    }
}

fn drawColoredCube(fb: *Framebuffer, mvp: Mat4, light_dir: Vec3, color: Vec3) void {
    const verts = makeCubeVerts(color);
    const indices = comptime blk: {
        var idx: [12][3]u32 = undefined;
        for (0..6) |fi| {
            const base: u32 = @intCast(fi * 4);
            idx[fi * 2] = .{ base, base + 1, base + 2 };
            idx[fi * 2 + 1] = .{ base, base + 2, base + 3 };
        }
        break :blk idx;
    };
    for (indices) |tri| {
        fb.drawTriangle(verts[tri[0]], verts[tri[1]], verts[tri[2]], mvp, light_dir);
    }
}

fn makeCubeVerts(color: Vec3) [24]zreal.Vertex {
    const P = [8]Vec4{
        Vec4.init(-0.5, -0.5, 0.5, 1), Vec4.init(0.5, -0.5, 0.5, 1),
        Vec4.init(0.5, 0.5, 0.5, 1),   Vec4.init(-0.5, 0.5, 0.5, 1),
        Vec4.init(-0.5, -0.5, -0.5, 1), Vec4.init(0.5, -0.5, -0.5, 1),
        Vec4.init(0.5, 0.5, -0.5, 1),  Vec4.init(-0.5, 0.5, -0.5, 1),
    };
    const N = [6]Vec3{
        Vec3.init(0, 0, 1), Vec3.init(0, 0, -1), Vec3.init(1, 0, 0),
        Vec3.init(-1, 0, 0), Vec3.init(0, 1, 0), Vec3.init(0, -1, 0),
    };
    const F = [6][4]u32{
        .{ 0, 1, 2, 3 }, .{ 5, 4, 7, 6 }, .{ 1, 5, 6, 2 },
        .{ 4, 0, 3, 7 }, .{ 3, 2, 6, 7 }, .{ 4, 5, 1, 0 },
    };
    var verts: [24]zreal.Vertex = undefined;
    for (F, 0..) |face, fi| {
        for (face, 0..) |vi, j| {
            verts[fi * 4 + j] = .{ .pos = P[vi], .color = color, .normal = N[fi] };
        }
    }
    return verts;
}

fn drawWall(fb: *Framebuffer, vp: Mat4, light_dir: Vec3, x: f32, z: f32, along_z: bool) void {
    const wall_color = Vec3.init(0.5, 0.45, 0.4);
    const model = if (along_z)
        Mat4.translation(x, 0.5, 0).mul(Mat4.scaling(0.2, 1.0, ARENA_SIZE * 2))
    else
        Mat4.translation(0, 0.5, z).mul(Mat4.scaling(ARENA_SIZE * 2, 1.0, 0.2));
    const mvp = vp.mul(model);
    drawColoredCube(fb, mvp, light_dir, wall_color);
}

// ��─ Entry Point ───────────────────────────────────────────────────────

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var fb = try Framebuffer.init(allocator, FB_WIDTH, FB_HEIGHT);
    defer fb.deinit();

    // Output buffer: ~45 bytes per pixel pair × width × (height/2) rows + HUD
    const out_buf_size = 50 * FB_WIDTH * (FB_HEIGHT / 2) + 256;
    const out_buf = try allocator.alloc(u8, out_buf_size);
    defer allocator.free(out_buf);

    // Raw terminal setup
    const tty = std.posix.STDIN_FILENO;
    const stdout_fd = std.posix.STDOUT_FILENO;
    const original_termios = try std.posix.tcgetattr(tty);

    var raw = original_termios;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

    try std.posix.tcsetattr(tty, .NOW, raw);
    defer std.posix.tcsetattr(tty, .NOW, original_termios) catch {};

    // Alternate screen + hide cursor
    try terminal.writeStr(stdout_fd, "\x1b[?1049h\x1b[?25l\x1b[2J");
    defer terminal.writeStr(stdout_fd, "\x1b[?25h\x1b[?1049l\x1b[0m") catch {};

    var state = initGame();

    var prev_time = clockNs();
    var frame_count: u32 = 0;
    var fps: u32 = TARGET_FPS;
    var fps_timer: u64 = 0;

    while (state.running) {
        const now = clockNs();
        const dt_ns = now -| prev_time;
        prev_time = now;
        const dt: f32 = @as(f32, @floatFromInt(dt_ns)) / @as(f32, @floatFromInt(std.time.ns_per_s));
        const clamped_dt = @min(dt, 0.1);

        state.time += clamped_dt;

        // FPS
        frame_count += 1;
        fps_timer += dt_ns;
        if (fps_timer >= std.time.ns_per_s) {
            fps = frame_count;
            frame_count = 0;
            fps_timer = 0;
        }

        // Input
        const input = readInput(tty);
        if (input.quit) break;

        if (input.forward) state.camera.moveForward(MOVE_SPEED * clamped_dt);
        if (input.backward) state.camera.moveForward(-MOVE_SPEED * clamped_dt);
        if (input.left) state.camera.moveRight(-MOVE_SPEED * clamped_dt);
        if (input.right) state.camera.moveRight(MOVE_SPEED * clamped_dt);
        if (input.turn_left) state.camera.rotate(-ROTATE_SPEED * clamped_dt, 0);
        if (input.turn_right) state.camera.rotate(ROTATE_SPEED * clamped_dt, 0);

        // Clamp to arena
        state.camera.pos = Vec4.init(
            std.math.clamp(state.camera.pos.x(), -ARENA_SIZE + 0.5, ARENA_SIZE - 0.5),
            state.camera.pos.y(),
            std.math.clamp(state.camera.pos.z(), -ARENA_SIZE + 0.5, ARENA_SIZE - 0.5),
            1,
        );

        // Spawn
        state.spawn_timer += clamped_dt;
        if (state.spawn_timer > 2.0) {
            state.spawn_timer = 0;
            spawnCube(&state);
        }

        // Physics
        updatePhysics(&state, clamped_dt);

        // Render 3D scene to framebuffer
        renderFrame(&fb, &state);

        // Convert framebuffer to ANSI terminal output
        var pos = terminal.renderToBuffer(&fb, out_buf);

        // Append HUD line
        const hud = std.fmt.bufPrint(out_buf[pos..], "\x1b[{};1H\x1b[0m Score: {} | FPS: {} | WASD=move Q/E=turn X=quit  ", .{
            FB_HEIGHT / 2 + 1,
            state.score,
            fps,
        }) catch &[_]u8{};
        pos += hud.len;

        // Single write to stdout
        try terminal.writeStr(stdout_fd, out_buf[0..pos]);

        // Frame limiter
        const frame_elapsed = clockNs() -| prev_time;
        if (frame_elapsed < FRAME_NS) {
            _ = std.c.nanosleep(&.{ .sec = 0, .nsec = @intCast(FRAME_NS - frame_elapsed) }, null);
        }
    }
}

fn clockNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}
