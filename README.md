# zreal — Zig SIMD Game Engine

A **web-first 3D game engine** built from scratch in pure Zig. Zero external libraries. Compiles to **WebAssembly** with hardware SIMD acceleration, renders via **WebGL2** in the browser.

**Live Demo**: Space Shooter — 60+ enemy types, particle explosions, combo scoring, power-ups. All physics and math computed in WASM SIMD.

```
┌─────────────────────────────────────────────────────────────┐
│  Zig (@Vector → WASM v128)    │    JS (WebGL2 rendering)   │
│  ─────────────────────────────│────────────────────────────│
│  • Mat4 × Vec4 (FMA)          │  • Shader compilation       │
│  • Collision detection         │  • Geometry upload (VAO)    │
│  • Particle physics            │  • Draw calls               │
│  • Game logic + AI             │  • Input → WASM calls       │
│  • Scene graph → MVP matrices  │  • HUD overlay              │
│                                │                             │
│  Writes to WASM linear memory ──→ JS reads Float32Array     │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Prerequisites

- [Zig 0.16+](https://ziglang.org/download/)
- A modern browser (Chrome, Firefox, Safari — all support WASM SIMD + WebGL2)
- Python 3 (for local HTTP server) or any static file server

### Build & Run

```bash
# Clone
git clone https://github.com/user/zreal && cd zreal

# Build WASM
zig build wasm

# Serve locally (pick one)
npx serve web
# or
bunx serve web

# Open http://localhost:3000
```

### Other Build Targets

```bash
zig build                           # Native desktop build
zig build run                       # Run native (terminal software renderer)
zig build run -Doptimize=ReleaseFast # Optimized native (full SIMD)
zig build test                      # Run all tests (math, renderer)
zig build wasm                      # Build WASM → web/zreal.wasm
```

---

## Architecture

### Two-layer design

**Zig (WASM)** owns all state and computation. **JS** owns rendering and input. They communicate through WASM linear memory and exported functions.

```
Browser                                    WASM Module (Zig)
┌──────────────────────────┐              ┌──────────────────────────┐
│  index.html              │              │  wasm_entry.zig          │
│  engine.js               │  export fn   │                          │
│                          │ ◄──────────► │  Game State              │
│  ┌─ WebGL2 Renderer ──┐ │              │  ├── Player position     │
│  │  Shaders (GLSL)     │ │  setInput() │  ├── Bullets [128]       │
│  │  Geometry (VAO)     │ │ ──────────► │  ├── Enemies [64]        │
│  │  Draw calls         │ │              │  ├── Particles [1024]    │
│  └─────────────────────┘ │  frame(dt)  │  └── Stars [200]         │
│                          │ ──────────► │                          │
│  ┌─ Read WASM Memory ─┐ │              │  Computation (SIMD)      │
│  │  getMvpPtr() ───────│─│──► Float32  │  ├── Mat4 mulCol (@mulAdd)│
│  │  getModelPtr() ─────│─│──► Array    │  ├── Collision (AABB)     │
│  │  getParticleDataPtr │ │    views    │  ├── Particle integration │
│  └─────────────────────┘ │              │  └── Wave AI              │
│                          │  getScore() │                          │
│  ┌─ HUD ───────────────┐ │ ◄────────── │  Output Buffers          │
│  │  Score, combo, HP   │ │              │  ├── mvp_buf[512×16] f32 │
│  │  Wave indicator     │ │              │  ├── model_buf[512×16]   │
│  └─────────────────────┘ │              │  ├── part_data[1024×8]   │
└──────────────────────────┘              │  └── render metadata     │
                                          └──────────────────────────┘
```

### Why this split?

- **Math in WASM SIMD**: `@Vector(4, f32)` compiles to `v128` — 4 floats processed in one instruction. A `Mat4 × Vec4` multiply uses 4 FMA instructions total.
- **Rendering in JS**: WebGL2 API is only accessible from JS. No point bridging every `gl.*` call through WASM — just pass the computed matrices.
- **Zero-copy data sharing**: JS creates `Float32Array` views directly into WASM linear memory. No serialization, no copying.

---

## WASM API Reference

All exported functions are accessible via `ZReal.wasm.exports` (or directly from any WASM loader).

### Lifecycle

| Function | Signature | Description |
|----------|-----------|-------------|
| `init()` | `() → void` | Initialize/reset game state. Spawns player, clears enemies, resets score. |
| `frame(dt)` | `(f32) → void` | Advance one frame. `dt` is delta time in seconds. Call from `requestAnimationFrame`. |
| `restart()` | `() → void` | Alias for `init()`. |

### Input

| Function | Signature | Description |
|----------|-----------|-------------|
| `setInput(x, y)` | `(f32, f32) → void` | Set player target position. `x` and `y` are normalized `[-1, 1]`. Maps to game field. |
| `setFire(on)` | `(u32) → void` | Enable/disable auto-fire. `1` = on, `0` = off. On by default. |
| `setAspect(a)` | `(f32) → void` | Set camera aspect ratio. Call on canvas resize: `setAspect(width / height)`. |

### State Queries

| Function | Returns | Description |
|----------|---------|-------------|
| `getScore()` | `u32` | Current score |
| `getCombo()` | `u32` | Current combo multiplier (resets after 2s without kills) |
| `getWave()` | `u32` | Current wave number (boss every 5th wave) |
| `getHP()` | `f32` | Player health (starts at 3) |
| `getGameState()` | `u32` | `0` = playing, `1` = dead |
| `getShield()` | `f32` | Shield time remaining (seconds) |
| `getTriple()` | `f32` | Triple-shot time remaining (seconds) |
| `getTime()` | `f32` | Total elapsed time (seconds) |
| `getShake()` | `f32` | Screen shake intensity (decays to 0) |

### Render Data

The engine writes all render data into WASM linear memory each frame. JS reads it directly through typed array views.

| Function | Returns | Description |
|----------|---------|-------------|
| `getRenderCount()` | `u32` | Number of objects to draw this frame |
| `getMvpPtr()` | `u32` | Byte offset to MVP matrix array in WASM memory |
| `getModelPtr()` | `u32` | Byte offset to model matrix array |
| `getVpPtr()` | `u32` | Byte offset to view-projection matrix (16 floats) |
| `getRenderKind(i)` | `u32` | Object type: `0`=player, `1`=bullet, `2`=enemy, `3`=particle, `4`=star, `5`=powerup, `6`=shield |
| `getRenderColor(i, c)` | `f32` | Color component (`c`: 0=R, 1=G, 2=B), range 0..1 |
| `getRenderGlow(i)` | `f32` | Emission/glow intensity (0 = none, 1 = full) |

#### Particle Data

| Function | Returns | Description |
|----------|---------|-------------|
| `getParticleCount()` | `u32` | Number of active particles |
| `getParticleDataPtr()` | `u32` | Byte offset to particle array. Each particle = 8 floats: `x, y, z, r, g, b, size, alpha` |

### Reading Matrices from WASM Memory

```javascript
const W = ZReal.wasm.exports;
const memory = W.memory;

// Call frame first — this computes all matrices
W.frame(deltaTime);

// View-Projection matrix (one per frame)
const vpMat = new Float32Array(memory.buffer, W.getVpPtr(), 16);

// Per-object matrices
const count = W.getRenderCount();
const mvpBase = W.getMvpPtr();
const modelBase = W.getModelPtr();

for (let i = 0; i < count; i++) {
  // Each matrix = 16 floats × 4 bytes = 64 bytes
  const mvp   = new Float32Array(memory.buffer, mvpBase + i * 64, 16);
  const model = new Float32Array(memory.buffer, modelBase + i * 64, 16);
  const kind  = W.getRenderKind(i);   // what type of object
  const r     = W.getRenderColor(i, 0);
  const g     = W.getRenderColor(i, 1);
  const b     = W.getRenderColor(i, 2);
  const glow  = W.getRenderGlow(i);

  // Use with WebGL:
  gl.uniformMatrix4fv(uMVP, false, mvp);
  gl.uniformMatrix4fv(uModel, false, model);
  gl.uniform3f(uColor, r, g, b);
  gl.uniform1f(uGlow, glow);
  gl.drawElements(gl.TRIANGLES, indexCount, gl.UNSIGNED_SHORT, 0);
}

// Particles (additive blending)
const pCount = W.getParticleCount();
const pData = new Float32Array(memory.buffer, W.getParticleDataPtr(), pCount * 8);
for (let i = 0; i < pCount; i++) {
  const o = i * 8;
  const pos   = [pData[o], pData[o+1], pData[o+2]];
  const color = [pData[o+3], pData[o+4], pData[o+5]];
  const size  = pData[o+6];
  const alpha = pData[o+7];
  // Draw as billboard quad with additive blending
}
```

---

## Zig Math Library (importable as `zreal`)

All types use `@Vector(N, f32)` — compiles to hardware SIMD on every target.

### Vec3

```zig
const zreal = @import("zreal");
const Vec3 = zreal.Vec3;

const a = Vec3.init(1, 2, 3);
const b = Vec3.init(4, 5, 6);

a.add(b)            // → Vec3 (5, 7, 9)        — SIMD add
a.sub(b)            // → Vec3 (-3, -3, -3)     — SIMD sub
a.scale(2.0)        // → Vec3 (2, 4, 6)        — SIMD mul by splat
a.dot(b)            // → f32 (32)              — SIMD mul + reduce
a.cross(b)          // → Vec3 (-3, 6, -3)      — SIMD shuffle + mul
a.length()          // → f32 (3.742)           — sqrt(dot(a,a))
a.normalize()       // → Vec3 (unit length)
a.lerp(b, 0.5)     // → Vec3 (2.5, 3.5, 4.5) — linear interpolation
a.negate()          // → Vec3 (-1, -2, -3)

// Component access
a.x()  // → 1.0
a.y()  // → 2.0
a.z()  // → 3.0
```

`Vec4` has the same API plus `.w()`. `Vec2` uses `@Vector(2, f32)`.

### Mat4

```zig
const Mat4 = zreal.Mat4;

// Constructors
Mat4.identity                           // 4×4 identity
Mat4.translation(x, y, z)              // translate
Mat4.scaling(x, y, z)                  // scale
Mat4.rotationX(radians)                // rotate around X
Mat4.rotationY(radians)                // rotate around Y
Mat4.rotationZ(radians)                // rotate around Z

// Camera
Mat4.lookAt(eye, target, up)           // view matrix (right-handed)
Mat4.perspective(fov, aspect, near, far) // perspective projection

// Operations
const result = a.mul(b);               // matrix × matrix (4 FMA ops per column)
const v = m.mulVec4(vec);              // matrix × vector
const t = m.transpose();               // transpose
const val = m.at(row, col);            // element access
```

**Performance**: `mul` and `mulVec4` use `@mulAdd` which compiles to FMA (Fused Multiply-Add) — one instruction does `a * b + c` with no intermediate rounding.

### Quat (Quaternion)

```zig
const Quat = zreal.Quat;

Quat.identity                              // (0, 0, 0, 1)
Quat.fromAxisAngle(ax, ay, az, angle)     // axis-angle → quaternion
q1.mul(q2)                                 // quaternion multiplication
q.conjugate()                              // negate xyz
q.normalize()                              // unit quaternion
q.toMat4()                                 // convert to rotation matrix
q1.slerp(q2, t)                           // spherical interpolation
```

---

## Project Structure

```
zreal/
├── build.zig                     # Build config: native + WASM targets
├── README.md                     # This file
│
├── src/
│   ├── main.zig                  # Native entry — terminal software renderer (363 lines)
│   ├── wasm_entry.zig            # WASM entry — game logic + exported API (575 lines)
│   ├── root.zig                  # Library root — public API exports
│   ├── math.zig                  # Math module re-export
│   ├── renderer.zig              # Renderer module re-export
│   │
│   ├── math/
│   │   ├── scalar.zig            # f32 type alias
│   │   ├── vec2.zig              # Vec2 — @Vector(2, f32)
│   │   ├── vec3.zig              # Vec3 — @Vector(4, f32), w=0 (fills 128-bit register)
│   │   ├── vec4.zig              # Vec4 — @Vector(4, f32)
│   │   ├── mat.zig               # Mat4 — column-major, @mulAdd FMA (251 lines)
│   │   └── quat.zig              # Quaternion — SIMD backed (168 lines)
│   │
│   └── renderer/
│       ├── framebuffer.zig       # CPU software rasterizer + z-buffer (228 lines)
│       ├── camera.zig            # FPS camera (yaw/pitch/position)
│       ├── mesh.zig              # Procedural geometry (cube, floor)
│       └── terminal.zig          # ANSI 24-bit color terminal output
│
├── web/
│   ├── index.html                # HTML host page + HUD overlay
│   ├── engine.js                 # JS: WASM loader, WebGL2 renderer, input handling
│   └── zreal.wasm                # Built by `zig build wasm` (~680 KB)
│
└── docs/
    ├── one-week-plan.md          # Day-by-day build plan
    └── implementation-guide.md   # Step-by-step guide to reimplement from scratch
```

---

## Building Your Own Game

### Step 1: Modify `wasm_entry.zig`

This is where all game logic lives. The pattern:

```zig
// 1. Define your state as global arrays (no allocator needed)
var enemies: [MAX_ENEMIES]Enemy = undefined;

// 2. Export init — called once from JS
export fn init() void {
    // set up initial state
}

// 3. Export frame — called every requestAnimationFrame
export fn frame(dt: f32) void {
    // update physics, AI, collisions
    // write MVP matrices to output buffers
    buildRender();
}

// 4. Export input handlers
export fn setInput(x: f32, y: f32) void { ... }

// 5. Export state queries for HUD
export fn getScore() u32 { return score; }

// 6. Build render list — write matrices for JS to read
fn buildRender() void {
    render_count = 0;
    // camera setup
    cached_vp = proj.mul(view);
    // for each object, compute model matrix and emit:
    emit(kind, color, glow, model_matrix);
}

fn emit(kind: u32, color: [3]f32, glow: f32, model: Mat4) void {
    const mvp = cached_vp.mul(model);
    storeMat4(mvp_buf[render_count * 16..], mvp);
    storeMat4(model_buf[render_count * 16..], model);
    render_kinds[render_count] = kind;
    render_colors[render_count] = color;
    render_count += 1;
}
```

### Step 2: Update `build.zig` exports

Add any new `export fn` names to the `export_symbol_names` list:

```zig
wasm.root_module.export_symbol_names = &.{
    "init", "frame", "restart",
    "setInput", "getScore",
    // ... add your functions here
    "getRenderCount", "getMvpPtr", "getModelPtr",
    // ... standard render data exports
};
```

### Step 3: Update `web/engine.js`

The render loop reads from WASM memory and draws:

```javascript
render() {
  const W = this.wasm.exports, mem = W.memory;
  const count = W.getRenderCount();

  for (let i = 0; i < count; i++) {
    const kind = W.getRenderKind(i);
    const mvp = new Float32Array(mem.buffer, W.getMvpPtr() + i * 64, 16);

    // Choose geometry based on kind
    if (kind === MY_SPHERE_TYPE) {
      gl.bindVertexArray(this.sphereVAO);
      gl.drawElements(gl.TRIANGLES, this.sphereN, ...);
    } else {
      gl.bindVertexArray(this.cubeVAO);
      gl.drawElements(gl.TRIANGLES, this.cubeN, ...);
    }
  }
}
```

### Step 4: Build and test

```bash
zig build wasm && cd web && python3 -m http.server 8080
```

---

## Performance Notes

### SIMD everywhere

| Operation | Native (x86) | Native (ARM) | WASM |
|-----------|-------------|-------------|------|
| `Vec4.add(a, b)` | SSE `addps` | NEON `fadd.4s` | `f32x4.add` |
| `Mat4.mulCol` (FMA) | AVX `vfmadd` | NEON `fmla.4s` | `f32x4.add(f32x4.mul(...), ...)` |
| `Vec3.dot` | SSE `mulps` + `haddps` | NEON `fmul` + `faddp` | `f32x4.mul` + reduction |
| `Vec3.cross` | SSE `shufps` + `mulps` | NEON `ext` + `fmul` | `i8x16.swizzle` + `f32x4.mul` |

Zig's `@Vector(4, f32)` maps directly to these instructions — no wrapper code, no function call overhead.

### Zero allocations in game loop

All state lives in fixed-size global arrays. No `std.mem.Allocator` calls during gameplay. This gives:
- Predictable frame times (no GC pauses, no allocation stalls)
- Works on `wasm32-freestanding` without a heap
- Cache-friendly sequential memory access

### Render batching

The engine writes all matrices into contiguous arrays. JS reads them as `Float32Array` views — zero-copy, no serialization. One `uniformMatrix4fv` call per object, no JS matrix math.

---

## Extending the Engine

### Add a new geometry type

1. Generate vertex data in `engine.js` `buildGeo()`
2. Add a new `kind` value in `wasm_entry.zig` `emit()`
3. Handle the new kind in `engine.js` `render()`

### Add new particle effects

Call `spawnExplosion()` or `addParticle()` from Zig when events happen:

```zig
fn onEnemyDeath(x: f32, y: f32) void {
    spawnExplosion(x, y, 1.0, 0.5, 0.2, 30); // 30 orange particles
    shake = 0.3;
}
```

### Custom shaders

Edit the GLSL in `engine.js` `buildShaders()`. The uniform interface:
- `uMVP` — model-view-projection matrix (column-major)
- `uM` — model matrix
- `uCol` — object color (vec3, 0..1)
- `uGlow` — emission intensity (float)
- `uKind` — object type (int, for per-type effects)
- `uTime` — elapsed time (for animation)
- `uLight` — light direction (vec3, normalized)

---

## Build Output

| Target | File | Size | Notes |
|--------|------|------|-------|
| WASM | `web/zreal.wasm` | ~680 KB | ReleaseFast, all exports included |
| Native | `zig-out/bin/zreal` | ~150 KB | Terminal software renderer |
| Tests | — | — | 40+ tests for math library |

## Requirements

- Zig 0.16.0+
- Browser with WebGL2 + WASM SIMD (Chrome 91+, Firefox 89+, Safari 16.4+)

## License

MIT
