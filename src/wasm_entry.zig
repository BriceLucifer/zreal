const std = @import("std");
const zreal = @import("zreal");
const Vec3 = zreal.Vec3;
const Vec4 = zreal.Vec4;
const Mat4 = zreal.Mat4;

// ── Constants ─────────────────────────────────────────────────────────

const BULLET_MAX: u32 = 128;
const ENEMY_MAX: u32 = 64;
const PARTICLE_MAX: u32 = 1024;
const STAR_MAX: u32 = 200;
const POWERUP_MAX: u32 = 8;
const FIELD_W: f32 = 12.0; // half-width
const FIELD_H: f32 = 16.0; // half-height
const PLAYER_SPEED: f32 = 14.0;
const BULLET_SPEED: f32 = 28.0;
const FIRE_RATE: f32 = 0.1; // seconds between shots
const ENEMY_BULLET_SPEED: f32 = 10.0;

// ── Types ─────────────────────────────────────────────────────────────

const Bullet = struct {
    x: f32, y: f32, vx: f32, vy: f32,
    friendly: bool, active: bool,
    kind: u8, // 0=normal, 1=triple
};

const Enemy = struct {
    x: f32, y: f32, vx: f32, vy: f32,
    hp: f32, max_hp: f32,
    kind: u8, // 0=basic, 1=fast, 2=tank, 3=boss
    color: [3]f32,
    fire_timer: f32,
    active: bool,
    entry_timer: f32, // smooth entry animation
};

const Particle = struct {
    x: f32, y: f32, z: f32,
    vx: f32, vy: f32, vz: f32,
    r: f32, g: f32, b: f32,
    life: f32, max_life: f32, size: f32,
};

const Star = struct { x: f32, y: f32, z: f32, speed: f32, brightness: f32 };

const Powerup = struct {
    x: f32, y: f32, kind: u8, // 0=triple, 1=shield, 2=bomb
    active: bool, time: f32,
};

// ── State ─────────────────────────────────────────────────────────────

var player_x: f32 = 0;
var player_y: f32 = -10;
var player_vx: f32 = 0;
var player_vy: f32 = 0;
var player_hp: f32 = 3;
var player_invincible: f32 = 0;
var player_shield: f32 = 0;
var player_triple: f32 = 0;
var fire_timer: f32 = 0;

var bullets: [BULLET_MAX]Bullet = undefined;
var enemies: [ENEMY_MAX]Enemy = undefined;
var particles: [PARTICLE_MAX]Particle = undefined;
var stars: [STAR_MAX]Star = undefined;
var powerups: [POWERUP_MAX]Powerup = undefined;

var score: u32 = 0;
var combo: u32 = 0;
var combo_timer: f32 = 0;
var wave: u32 = 0;
var wave_timer: f32 = 0;
var enemies_alive: u32 = 0;
var total_time: f32 = 0;
var game_state: u32 = 0; // 0=playing, 1=dead, 2=paused
var shake: f32 = 0;
var difficulty: f32 = 1.0;

// Input
var input_x: f32 = 0;
var input_y: f32 = 0;
var input_fire: bool = true; // auto-fire

// Camera
var cam_aspect: f32 = 1.0;

// Output
const OUT_MAX: u32 = 512;
var mvp_buf: [OUT_MAX * 16]f32 = undefined;
var model_buf: [OUT_MAX * 16]f32 = undefined;
var vp_mat: [16]f32 = undefined;
var cached_vp: Mat4 = Mat4.identity;
var render_count: u32 = 0;
var render_kinds: [OUT_MAX]u32 = undefined; // 0=player,1=bullet,2=enemy,3=particle,4=star,5=powerup,6=shield
var render_colors: [OUT_MAX][3]f32 = undefined;
var render_glow: [OUT_MAX]f32 = undefined;

// Particle output
var part_data: [PARTICLE_MAX * 8]f32 = undefined;
var part_count: u32 = 0;

// RNG
var rng: u32 = 54321;
fn rf() f32 { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return @as(f32, @floatFromInt(rng % 10000)) / 10000.0; }
fn rfRange(lo: f32, hi: f32) f32 { return lo + rf() * (hi - lo); }

// ── Init ──────────────────────────────────────────────────────────────

export fn init() void {
    player_x = 0; player_y = -10; player_vx = 0; player_vy = 0;
    player_hp = 3; player_invincible = 2.0; player_shield = 0; player_triple = 0;
    fire_timer = 0; score = 0; combo = 0; combo_timer = 0;
    wave = 0; wave_timer = 1.0; enemies_alive = 0;
    total_time = 0; game_state = 0; shake = 0; difficulty = 1.0;
    input_x = 0; input_y = 0;

    for (&bullets) |*b| b.active = false;
    for (&enemies) |*e| e.active = false;
    for (&particles) |*p| p.life = 0;
    for (&powerups) |*p| p.active = false;

    // Init stars
    for (&stars) |*s| {
        s.x = rfRange(-FIELD_W * 2, FIELD_W * 2);
        s.y = rfRange(-FIELD_H * 2, FIELD_H * 2);
        s.z = rfRange(-5, -1);
        s.speed = rfRange(3, 10);
        s.brightness = rfRange(0.2, 1.0);
    }
}

// ── Frame ─────────────────────────────────────────────────────────────

export fn frame(dt: f32) void {
    if (game_state == 1) {
        updateParticles(dt);
        updateStars(dt);
        buildRender();
        return;
    }

    total_time += dt;
    difficulty = 1.0 + @as(f32, @floatFromInt(wave)) * 0.15;

    // Player movement (smooth)
    const target_x = input_x * FIELD_W * 0.9;
    const target_y = input_y * FIELD_H * 0.5 - 5.0;
    player_vx = (target_x - player_x) * 8.0;
    player_vy = (target_y - player_y) * 8.0;
    player_x += player_vx * dt;
    player_y += player_vy * dt;
    player_x = std.math.clamp(player_x, -FIELD_W + 0.5, FIELD_W - 0.5);
    player_y = std.math.clamp(player_y, -FIELD_H + 1, -2);

    // Timers
    if (player_invincible > 0) player_invincible -= dt;
    if (player_shield > 0) player_shield -= dt;
    if (player_triple > 0) player_triple -= dt;
    if (combo_timer > 0) { combo_timer -= dt; if (combo_timer <= 0) combo = 0; }
    if (shake > 0) shake *= 0.92;

    // Auto-fire
    fire_timer -= dt;
    if (input_fire and fire_timer <= 0) {
        fireBullet(player_x, player_y + 0.5, 0, BULLET_SPEED, true);
        if (player_triple > 0) {
            fireBullet(player_x - 0.3, player_y + 0.3, -3.0, BULLET_SPEED, true);
            fireBullet(player_x + 0.3, player_y + 0.3, 3.0, BULLET_SPEED, true);
        }
        fire_timer = FIRE_RATE;
    }

    // Wave spawning
    wave_timer -= dt;
    if (wave_timer <= 0 and enemies_alive == 0) {
        wave += 1;
        spawnWave();
        wave_timer = 999; // wait until all dead
    }
    if (enemies_alive == 0 and wave_timer > 100) {
        wave_timer = 1.5; // short delay before next wave
    }

    // Update bullets
    for (&bullets) |*b| {
        if (!b.active) continue;
        b.x += b.vx * dt;
        b.y += b.vy * dt;
        if (b.y > FIELD_H + 1 or b.y < -FIELD_H - 1 or
            b.x > FIELD_W + 1 or b.x < -FIELD_W - 1) b.active = false;
    }

    // Update enemies
    enemies_alive = 0;
    for (&enemies) |*e| {
        if (!e.active) continue;
        enemies_alive += 1;

        if (e.entry_timer > 0) {
            e.entry_timer -= dt;
            continue;
        }

        e.x += e.vx * dt;
        e.y += e.vy * dt;

        // Bounce off sides
        if (e.x < -FIELD_W + 0.5 or e.x > FIELD_W - 0.5) e.vx = -e.vx;
        // Clamp to upper half
        if (e.y < -3) { e.vy = @abs(e.vy) * 0.5; e.y = -3; }
        if (e.y > FIELD_H - 1) { e.vy = -@abs(e.vy); }

        // Enemy fire
        e.fire_timer -= dt;
        if (e.fire_timer <= 0) {
            const aim_x = player_x - e.x;
            const aim_y = player_y - e.y;
            const aim_len = @sqrt(aim_x * aim_x + aim_y * aim_y);
            if (aim_len > 0.1) {
                fireBullet(e.x, e.y - 0.3, aim_x / aim_len * ENEMY_BULLET_SPEED, aim_y / aim_len * ENEMY_BULLET_SPEED, false);
            }
            e.fire_timer = if (e.kind == 3) 0.6 / difficulty else 2.0 / difficulty;
        }

        // Off bottom = remove
        if (e.y < -FIELD_H - 2) e.active = false;
    }

    // Collision: player bullets → enemies
    for (&bullets) |*b| {
        if (!b.active or !b.friendly) continue;
        for (&enemies) |*e| {
            if (!e.active or e.entry_timer > 0) continue;
            const size: f32 = if (e.kind == 3) 1.5 else 0.6;
            if (@abs(b.x - e.x) < size and @abs(b.y - e.y) < size) {
                b.active = false;
                e.hp -= 1;
                spawnHitParticles(b.x, b.y, e.color[0], e.color[1], e.color[2], 5);
                if (e.hp <= 0) {
                    e.active = false;
                    combo += 1;
                    combo_timer = 2.0;
                    const base_pts: u32 = switch (e.kind) {
                        0 => 100, 1 => 150, 2 => 200, 3 => 1000, else => 50,
                    };
                    score += base_pts * combo;
                    spawnExplosion(e.x, e.y, e.color[0], e.color[1], e.color[2],
                        if (e.kind == 3) 60 else 20);
                    shake = if (e.kind == 3) 0.8 else 0.2;
                    // Chance to drop powerup
                    if (rf() < 0.15) spawnPowerup(e.x, e.y);
                }
                break;
            }
        }
    }

    // Collision: enemy bullets → player
    if (player_invincible <= 0) {
        for (&bullets) |*b| {
            if (!b.active or b.friendly) continue;
            if (@abs(b.x - player_x) < 0.5 and @abs(b.y - player_y) < 0.5) {
                b.active = false;
                if (player_shield > 0) {
                    player_shield = 0;
                    spawnHitParticles(player_x, player_y, 0.3, 0.6, 1.0, 15);
                } else {
                    player_hp -= 1;
                    player_invincible = 1.5;
                    shake = 0.5;
                    spawnExplosion(player_x, player_y, 1, 0.5, 0.2, 15);
                    if (player_hp <= 0) {
                        game_state = 1;
                        spawnExplosion(player_x, player_y, 1, 0.8, 0.3, 50);
                        shake = 1.0;
                    }
                }
            }
        }
    }

    // Collision: player → powerups
    for (&powerups) |*p| {
        if (!p.active) continue;
        p.y -= 2.0 * dt;
        p.time += dt;
        if (p.y < -FIELD_H - 1) { p.active = false; continue; }
        if (@abs(p.x - player_x) < 1.0 and @abs(p.y - player_y) < 1.0) {
            p.active = false;
            switch (p.kind) {
                0 => player_triple = 8.0,
                1 => player_shield = 10.0,
                2 => bombAll(),
                else => {},
            }
            spawnHitParticles(p.x, p.y, 1, 1, 0.5, 10);
        }
    }

    updateParticles(dt);
    updateStars(dt);
    buildRender();
}

// ── Spawning ──────────────────────────────────────────────────────────

fn spawnWave() void {
    if (wave % 5 == 0 and wave > 0) {
        // Boss wave
        spawnEnemy(0, FIELD_H + 2, 0, -1.0, 20 + @as(f32, @floatFromInt(wave)) * 2, 3);
    } else {
        const count: u32 = @min(12, 4 + wave);
        for (0..count) |i| {
            const fi = @as(f32, @floatFromInt(i));
            const cols = @as(f32, @floatFromInt(@min(count, 6)));
            const row = fi / cols;
            const col = @mod(fi, cols);
            const x = (col - cols * 0.5 + 0.5) * 2.5;
            const y = FIELD_H + 2 + row * 2.0;
            const kind: u8 = if (rf() < 0.2) 1 else if (rf() < 0.15) 2 else 0;
            spawnEnemy(x, y, rfRange(-1, 1), -rfRange(0.5, 2.0) * difficulty, if (kind == 2) 3 else 1, kind);
        }
    }
}

fn spawnEnemy(x: f32, y: f32, vx: f32, vy: f32, hp: f32, kind: u8) void {
    for (&enemies) |*e| {
        if (!e.active) {
            const color: [3]f32 = switch (kind) {
                0 => .{ 0.2, 0.8, 0.4 }, // basic = green
                1 => .{ 1.0, 0.6, 0.2 }, // fast = orange
                2 => .{ 0.7, 0.2, 0.2 }, // tank = red
                3 => .{ 0.9, 0.2, 0.9 }, // boss = purple
                else => .{ 1, 1, 1 },
            };
            e.* = .{
                .x = x, .y = y, .vx = vx, .vy = vy,
                .hp = hp, .max_hp = hp, .kind = kind, .color = color,
                .fire_timer = rfRange(1.0, 3.0) / difficulty,
                .active = true, .entry_timer = 0.3,
            };
            return;
        }
    }
}

fn fireBullet(x: f32, y: f32, vx: f32, vy: f32, friendly: bool) void {
    for (&bullets) |*b| {
        if (!b.active) {
            b.* = .{ .x = x, .y = y, .vx = vx, .vy = vy, .friendly = friendly, .active = true, .kind = 0 };
            return;
        }
    }
}

fn spawnPowerup(x: f32, y: f32) void {
    for (&powerups) |*p| {
        if (!p.active) {
            p.* = .{ .x = x, .y = y, .kind = @intCast(@as(u32, @intFromFloat(rf() * 3)) % 3), .active = true, .time = 0 };
            return;
        }
    }
}

fn bombAll() void {
    for (&enemies) |*e| {
        if (e.active) {
            e.hp -= 5;
            if (e.hp <= 0) {
                e.active = false;
                score += 50 * (combo + 1);
                combo += 1;
                combo_timer = 2.0;
                spawnExplosion(e.x, e.y, e.color[0], e.color[1], e.color[2], 15);
            }
        }
    }
    shake = 1.0;
}

// ── Particles ─────────────────────────────────────────────────────────

fn spawnExplosion(x: f32, y: f32, r: f32, g: f32, b: f32, count: u32) void {
    for (0..count) |_| {
        const angle = rf() * std.math.pi * 2.0;
        const spd = rfRange(2, 12);
        const life = rfRange(0.3, 1.0);
        addParticle(x, y, 0, @cos(angle) * spd, @sin(angle) * spd, rfRange(-2, 4),
            r + rf() * 0.3, g + rf() * 0.3, b + rf() * 0.3, life, rfRange(0.04, 0.15));
    }
}

fn spawnHitParticles(x: f32, y: f32, r: f32, g: f32, b: f32, count: u32) void {
    for (0..count) |_| {
        const angle = rf() * std.math.pi * 2.0;
        const spd = rfRange(3, 8);
        addParticle(x, y, 0, @cos(angle) * spd, @sin(angle) * spd, rfRange(0, 3),
            r, g, b, rfRange(0.2, 0.5), rfRange(0.02, 0.06));
    }
}

fn addParticle(x: f32, y: f32, z: f32, vx: f32, vy: f32, vz: f32, r: f32, g: f32, b: f32, life: f32, size: f32) void {
    for (&particles) |*p| {
        if (p.life <= 0) {
            p.* = .{ .x = x, .y = y, .z = z, .vx = vx, .vy = vy, .vz = vz,
                .r = @min(r, 1.5), .g = @min(g, 1.5), .b = @min(b, 1.5),
                .life = life, .max_life = life, .size = size };
            return;
        }
    }
}

fn updateParticles(dt: f32) void {
    part_count = 0;
    for (&particles) |*p| {
        if (p.life <= 0) continue;
        p.life -= dt;
        p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
        p.vx *= 0.97; p.vy *= 0.97; p.vz *= 0.95;
        p.vz -= 3.0 * dt; // gravity on z

        if (p.life > 0 and part_count < PARTICLE_MAX) {
            const a = p.life / p.max_life;
            const i = part_count * 8;
            part_data[i] = p.x; part_data[i + 1] = p.z * 0.3; part_data[i + 2] = p.y;
            part_data[i + 3] = p.r; part_data[i + 4] = p.g; part_data[i + 5] = p.b;
            part_data[i + 6] = p.size * (0.3 + a * 0.7);
            part_data[i + 7] = a * a; // quadratic fade
            part_count += 1;
        }
    }
}

fn updateStars(dt: f32) void {
    for (&stars) |*s| {
        s.y -= s.speed * dt;
        if (s.y < -FIELD_H * 2) {
            s.y = FIELD_H * 2;
            s.x = rfRange(-FIELD_W * 2, FIELD_W * 2);
        }
    }
}

// ── Input ─────────────────────────────────────────────────────────────

export fn setInput(x: f32, y: f32) void { input_x = x; input_y = y; }
export fn setFire(on: u32) void { input_fire = on != 0; }
export fn restart() void { init(); }
export fn setAspect(a: f32) void { cam_aspect = a; }

// ── Getters ───────────────────────────────────────────────────────────

export fn getScore() u32 { return score; }
export fn getCombo() u32 { return combo; }
export fn getWave() u32 { return wave; }
export fn getHP() f32 { return player_hp; }
export fn getGameState() u32 { return game_state; }
export fn getShield() f32 { return player_shield; }
export fn getTriple() f32 { return player_triple; }
export fn getTime() f32 { return total_time; }
export fn getShake() f32 { return shake; }

export fn getRenderCount() u32 { return render_count; }
export fn getMvpPtr() [*]const f32 { return &mvp_buf; }
export fn getModelPtr() [*]const f32 { return &model_buf; }
export fn getVpPtr() [*]const f32 { return &vp_mat; }
export fn getRenderKind(i: u32) u32 { return if (i < render_count) render_kinds[i] else 99; }
export fn getRenderColor(i: u32, c: u32) f32 { return if (i < render_count) render_colors[i][c] else 0; }
export fn getRenderGlow(i: u32) f32 { return if (i < render_count) render_glow[i] else 0; }
export fn getParticleCount() u32 { return part_count; }
export fn getParticleDataPtr() [*]const f32 { return &part_data; }

// ── Build render ──────────────────────────────────────────────────────

fn buildRender() void {
    render_count = 0;

    // Camera: top-down-ish, slightly tilted
    const shake_x = if (shake > 0.01) rfRange(-shake, shake) else 0;
    const shake_y_val = if (shake > 0.01) rfRange(-shake, shake) else 0;
    const eye = Vec4.init(shake_x, 22, -4 + shake_y_val, 1);
    const target = Vec4.init(0, 0, 0, 1);
    const up = Vec4.init(0, 0, 1, 0);
    const view = Mat4.lookAt(eye, target, up);
    const proj = Mat4.perspective(0.9, cam_aspect, 0.1, 100.0);
    cached_vp = proj.mul(view);
    storeMat4(&vp_mat, cached_vp);

    // Stars
    for (&stars) |s| {
        const bright = s.brightness;
        emit(4, .{ bright, bright, bright * 0.9 }, bright,
            Mat4.translation(s.x, s.z, s.y).mul(Mat4.scaling(0.04, 0.04, 0.04)));
    }

    // Player
    if (game_state == 0) {
        const blink = if (player_invincible > 0) @sin(total_time * 20) * 0.5 + 0.5 else 1.0;
        emit(0, .{ 0.3 * blink, 0.7 * blink, 1.0 * blink }, 0.3,
            Mat4.translation(player_x, 0, player_y).mul(Mat4.scaling(0.8, 0.3, 1.0)));

        // Engine glow
        emit(0, .{ 0.2, 0.5, 1.0 }, 0.8,
            Mat4.translation(player_x, 0, player_y - 0.6).mul(Mat4.scaling(0.3, 0.2, 0.4)));

        // Shield
        if (player_shield > 0) {
            const sa = @min(1.0, player_shield) * 0.3;
            emit(6, .{ 0.2, 0.5, 1.0 }, sa,
                Mat4.translation(player_x, 0, player_y).mul(Mat4.scaling(1.8, 0.5, 1.8)));
        }
    }

    // Bullets
    for (&bullets) |b| {
        if (!b.active) continue;
        if (b.friendly) {
            emit(1, .{ 0.4, 0.8, 1.0 }, 0.9,
                Mat4.translation(b.x, 0, b.y).mul(Mat4.scaling(0.12, 0.12, 0.4)));
        } else {
            emit(1, .{ 1.0, 0.3, 0.2 }, 0.7,
                Mat4.translation(b.x, 0, b.y).mul(Mat4.scaling(0.15, 0.15, 0.3)));
        }
    }

    // Enemies
    for (&enemies) |e| {
        if (!e.active) continue;
        const s: f32 = switch (e.kind) {
            1 => 0.7, 2 => 1.2, 3 => 2.5, else => 0.8,
        };
        const glow_val: f32 = if (e.entry_timer > 0) 0.5 else (1.0 - e.hp / e.max_hp) * 0.3;
        emit(2, e.color, glow_val,
            Mat4.translation(e.x, 0, e.y)
                .mul(Mat4.rotationY(total_time * 0.5))
                .mul(Mat4.scaling(s, s * 0.4, s)));
    }

    // Powerups
    for (&powerups) |p| {
        if (!p.active) continue;
        const col: [3]f32 = switch (p.kind) {
            0 => .{ 1, 0.8, 0.2 }, // triple = gold
            1 => .{ 0.3, 0.6, 1.0 }, // shield = blue
            2 => .{ 1, 0.3, 0.3 }, // bomb = red
            else => .{ 1, 1, 1 },
        };
        emit(5, col, 0.6,
            Mat4.translation(p.x, 0, p.y)
                .mul(Mat4.rotationY(p.time * 3.0))
                .mul(Mat4.scaling(0.4, 0.4, 0.4)));
    }
}

fn emit(kind: u32, color: [3]f32, glow_val: f32, model: Mat4) void {
    if (render_count >= OUT_MAX) return;
    const i = render_count;
    render_kinds[i] = kind;
    render_colors[i] = color;
    render_glow[i] = glow_val;
    storeMat4(mvp_buf[i * 16 ..][0..16], cached_vp.mul(model));
    storeMat4(model_buf[i * 16 ..][0..16], model);
    render_count += 1;
}

fn storeMat4(out: *[16]f32, m: Mat4) void {
    inline for (0..4) |col| {
        inline for (0..4) |row| {
            out[col * 4 + row] = m.cols[col][row];
        }
    }
}
