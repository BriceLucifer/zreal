# zreal Game Engine — Engineering Guide

A complete, from-scratch guide to building a game engine in Zig. No prior game engine knowledge assumed. Each chapter explains the **why**, the **what**, the **how**, and gives Zig-specific implementation guidance.

---

## Table of Contents

1. [How a Game Engine Works](#1-how-a-game-engine-works)
2. [The Game Loop](#2-the-game-loop)
3. [Math Library (SIMD)](#3-math-library-simd)
4. [Memory Management](#4-memory-management)
5. [Platform Layer (Window & Input)](#5-platform-layer-window--input)
6. [Software Rasterizer](#6-software-rasterizer)
7. [GPU Rendering (Metal / Vulkan)](#7-gpu-rendering-metal--vulkan)
8. [Entity-Component-System (ECS)](#8-entity-component-system-ecs)
9. [Physics Engine](#9-physics-engine)
10. [Audio Engine](#10-audio-engine)
11. [Asset Pipeline](#11-asset-pipeline)
12. [Scene Graph & Cameras](#12-scene-graph--cameras)
13. [Suggested Build Order](#13-suggested-build-order)

---

## 1. How a Game Engine Works

### The Big Picture

A game engine is a **real-time simulation loop**. Every frame (~16ms at 60fps), it:

1. **Reads input** — keyboard, mouse, gamepad
2. **Updates state** — physics, AI, game logic
3. **Renders** — draws everything to the screen
4. **Presents** — swaps the framebuffer so the user sees the new frame

That's it. Everything else — physics, audio, networking, scripting — is a subsystem that plugs into this loop.

### Architecture Layers

```
┌─────────────────────────────────┐
│          Game / App             │  ← Your game logic
├─────────────────────────────────┤
│     Scene Graph / ECS           │  ← Organizes entities
├──────────┬──────────┬───────────┤
│ Renderer │ Physics  │  Audio    │  ← Simulation subsystems
├──────────┴──────────┴───────────┤
│         Math Library            │  ← Vectors, matrices, SIMD
├─────────────────────────────────┤
│     Memory Management           │  ← Allocators
├─────────────────────────────────┤
│      Platform Layer             │  ← OS windows, input, file I/O
└─────────────────────────────────┘
```

You build bottom-up. Each layer only depends on layers below it.

---

## 2. The Game Loop

### Concept

The simplest game loop:

```
while (running) {
    processInput();
    update(delta_time);
    render();
}
```

But this has a problem: `delta_time` varies per frame. Physics becomes non-deterministic — a fast machine simulates differently from a slow one.

### Fixed Timestep with Interpolation

The industry-standard solution. Physics runs at a **fixed rate** (e.g., 60Hz), rendering runs as fast as possible, and you **interpolate** between physics states for smooth visuals.

```
const FIXED_DT = 1.0 / 60.0;  // 16.67ms
var accumulator: f64 = 0.0;
var previous_time = getTime();

while (running) {
    const current_time = getTime();
    var frame_time = current_time - previous_time;
    previous_time = current_time;

    // Clamp to avoid spiral of death
    if (frame_time > 0.25) frame_time = 0.25;

    accumulator += frame_time;

    processInput();

    // Fixed-rate physics updates
    while (accumulator >= FIXED_DT) {
        previous_state = current_state;
        update(current_state, FIXED_DT);
        accumulator -= FIXED_DT;
    }

    // Interpolation factor for rendering
    const alpha = accumulator / FIXED_DT;
    const render_state = lerp(previous_state, current_state, alpha);
    render(render_state);
}
```

### Key Concepts

- **Spiral of death**: If `update()` takes longer than `FIXED_DT`, the accumulator grows unboundedly. The clamp at 0.25s prevents this — the simulation slows down instead of exploding.
- **Interpolation (`alpha`)**: Rendering happens between two physics states. `alpha = 0.0` means "show previous state", `alpha = 1.0` means "show current state". This gives smooth motion even when physics runs at a lower rate than rendering.

### Zig Implementation Notes

- Use `std.time.Timer` or `std.posix.clock_gettime` for high-resolution timing
- Store `previous_state` and `current_state` as separate copies (not pointers to the same data) so interpolation has two distinct snapshots

---

## 3. Math Library (SIMD)

This is the foundation of everything. Every position, rotation, color, and transformation flows through your math types.

### Why SIMD Matters

**SIMD** (Single Instruction, Multiple Data) processes 4 floats in a single CPU instruction. A `Vec4` add without SIMD is 4 separate adds. With SIMD, it's **one** instruction.

Zig makes this trivial: `@Vector(4, f32)` compiles to the best SIMD instructions for the target CPU automatically (SSE4.2 on x86, NEON on ARM).

### Vec2, Vec3, Vec4

```zig
// Vec4 backed by hardware SIMD
pub const Vec4 = struct {
    v: @Vector(4, f32),

    pub fn init(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return .{ .v = .{ x, y, z, w } };
    }

    pub fn add(a: Vec4, b: Vec4) Vec4 {
        return .{ .v = a.v + b.v };  // single SIMD instruction
    }

    pub fn sub(a: Vec4, b: Vec4) Vec4 {
        return .{ .v = a.v - b.v };
    }

    pub fn scale(a: Vec4, s: f32) Vec4 {
        return .{ .v = a.v * @as(@Vector(4, f32), @splat(s)) };
    }

    pub fn dot(a: Vec4, b: Vec4) f32 {
        return @reduce(.Add, a.v * b.v);
    }

    pub fn length(a: Vec4) f32 {
        return @sqrt(dot(a, a));
    }

    pub fn normalize(a: Vec4) Vec4 {
        const len = length(a);
        return scale(a, 1.0 / len);
    }

    // Access individual components
    pub fn x(self: Vec4) f32 { return self.v[0]; }
    pub fn y(self: Vec4) f32 { return self.v[1]; }
    pub fn z(self: Vec4) f32 { return self.v[2]; }
    pub fn w(self: Vec4) f32 { return self.v[3]; }
};
```

**Vec3 trick**: Store Vec3 as `@Vector(4, f32)` with `w = 0` for positions or `w = 1` for directions. This wastes 4 bytes but keeps everything SIMD-aligned and lets you reuse the Vec4 operations. The alternative is `@Vector(3, f32)` which may not map as cleanly to 128-bit SIMD registers on all architectures.

### Vec2

For 2D, you have two choices:
- `@Vector(2, f32)` — works but doesn't fill a full SIMD register
- `@Vector(4, f32)` with z=0, w=0 — wastes space but uniform with Vec4

For a 3D engine, use `@Vector(4, f32)` everywhere. For a 2D engine, `@Vector(2, f32)` is fine.

### Cross Product (Vec3 only)

```zig
pub fn cross(a: Vec4, b: Vec4) Vec4 {
    // a × b = (a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x, 0)
    const a_yzx = @shuffle(f32, a.v, undefined, [4]i32{ 1, 2, 0, 3 });
    const b_yzx = @shuffle(f32, b.v, undefined, [4]i32{ 1, 2, 0, 3 });
    const result = a_yzx * @shuffle(f32, b.v, undefined, [4]i32{ 2, 0, 1, 3 })
                 - b_yzx * @shuffle(f32, a.v, undefined, [4]i32{ 2, 0, 1, 3 });
    return .{ .v = .{ result[0], result[1], result[2], 0.0 } };
}
```

`@shuffle` maps to SIMD shuffle/swizzle instructions.

### Mat4 (4x4 Matrix)

Matrices represent transformations: translation, rotation, scaling, projection.

```zig
pub const Mat4 = struct {
    // Column-major: cols[0] is the first column
    cols: [4]@Vector(4, f32),

    pub const identity: Mat4 = .{ .cols = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    }};

    // Matrix * Vector: each column scaled by corresponding vector component, then summed
    pub fn mulVec(m: Mat4, v: @Vector(4, f32)) @Vector(4, f32) {
        const x: @Vector(4, f32) = @splat(v[0]);
        const y: @Vector(4, f32) = @splat(v[1]);
        const z: @Vector(4, f32) = @splat(v[2]);
        const w: @Vector(4, f32) = @splat(v[3]);
        return m.cols[0] * x + m.cols[1] * y + m.cols[2] * z + m.cols[3] * w;
    }

    // Matrix * Matrix
    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        return .{ .cols = .{
            a.mulVec(b.cols[0]),
            a.mulVec(b.cols[1]),
            a.mulVec(b.cols[2]),
            a.mulVec(b.cols[3]),
        }};
    }
};
```

**Column-major** is the standard in graphics (OpenGL, Vulkan, Metal all use it). The matrix is stored as 4 column vectors. This makes matrix-vector multiply very SIMD-friendly (each column gets scaled by one component of the vector).

### Essential Matrix Operations

You need to implement these:

| Function | What it does |
|----------|-------------|
| `translation(x, y, z)` | Move objects in space |
| `scaling(x, y, z)` | Resize objects |
| `rotationX/Y/Z(angle)` | Rotate around an axis |
| `lookAt(eye, target, up)` | Camera view matrix |
| `perspective(fov, aspect, near, far)` | Perspective projection |
| `orthographic(l, r, b, t, n, f)` | Orthographic projection |
| `inverse(m)` | Undo a transformation |
| `transpose(m)` | Swap rows and columns |

### Formulas

**Perspective projection** (maps 3D to 2D with depth):

```
f = 1 / tan(fov/2)

| f/aspect  0    0              0             |
| 0         f    0              0             |
| 0         0    (far+near)/(near-far)   -1   |
| 0         0    2*far*near/(near-far)    0   |
```

**LookAt** (positions and orients the camera):

```
zaxis = normalize(eye - target)     // forward (camera looks along -z)
xaxis = normalize(cross(up, zaxis)) // right
yaxis = cross(zaxis, xaxis)         // up

| xaxis.x  xaxis.y  xaxis.z  -dot(xaxis, eye) |
| yaxis.x  yaxis.y  yaxis.z  -dot(yaxis, eye) |
| zaxis.x  zaxis.y  zaxis.z  -dot(zaxis, eye) |
| 0        0        0         1                |
```

### Quaternions

Quaternions represent rotations without gimbal lock and are cheaper to interpolate than matrices.

A quaternion is `q = w + xi + yj + zk` — store as `@Vector(4, f32)` where `v = {x, y, z, w}`.

Key operations:
- **Multiply** (combines rotations): `q1 * q2`
- **Conjugate** (inverts rotation): `(-x, -y, -z, w)`
- **Normalize**: quaternions must stay unit-length
- **To Mat4**: convert to matrix for rendering
- **Slerp**: spherical linear interpolation for smooth rotation blending

```zig
pub const Quat = struct {
    v: @Vector(4, f32),  // x, y, z, w

    pub fn fromAxisAngle(axis: Vec4, angle: f32) Quat {
        const half = angle * 0.5;
        const s = @sin(half);
        const c = @cos(half);
        const n = axis.normalize();
        return .{ .v = .{ n.v[0] * s, n.v[1] * s, n.v[2] * s, c } };
    }

    pub fn mul(a: Quat, b: Quat) Quat {
        // Hamilton product
        return .{ .v = .{
            a.v[3]*b.v[0] + a.v[0]*b.v[3] + a.v[1]*b.v[2] - a.v[2]*b.v[1],
            a.v[3]*b.v[1] - a.v[0]*b.v[2] + a.v[1]*b.v[3] + a.v[2]*b.v[0],
            a.v[3]*b.v[2] + a.v[0]*b.v[1] - a.v[1]*b.v[0] + a.v[2]*b.v[3],
            a.v[3]*b.v[3] - a.v[0]*b.v[0] - a.v[1]*b.v[1] - a.v[2]*b.v[2],
        }};
    }

    pub fn toMat4(q: Quat) Mat4 {
        const x = q.v[0]; const y = q.v[1];
        const z = q.v[2]; const w = q.v[3];
        return .{ .cols = .{
            .{ 1-2*(y*y+z*z), 2*(x*y+w*z),   2*(x*z-w*y),   0 },
            .{ 2*(x*y-w*z),   1-2*(x*x+z*z), 2*(y*z+w*x),   0 },
            .{ 2*(x*z+w*y),   2*(y*z-w*x),   1-2*(x*x+y*y), 0 },
            .{ 0,             0,             0,              1 },
        }};
    }
};
```

### Testing Your Math

Write tests for every operation. Compare against known values:
- `dot([1,0,0,0], [0,1,0,0])` should be `0`
- `cross([1,0,0,0], [0,1,0,0])` should be `[0,0,1,0]`
- `identity * v` should equal `v`
- `inverse(m) * m` should equal `identity` (within epsilon)
- `normalize(v).length()` should be `1.0`

Use `std.testing.expectApproxEqAbs` for float comparisons.

---

## 4. Memory Management

### Why Custom Allocators

Game engines need:
- **Predictable performance**: `malloc` can stall for microseconds. Arenas never stall.
- **Cache locality**: Allocate related objects contiguously in memory.
- **Fast bulk deallocation**: Free everything from a frame in one shot.
- **Zero fragmentation**: Pool allocators prevent fragmentation entirely.

### Arena Allocator

An arena is a bump allocator: it has a big block of memory and a cursor. Allocation just advances the cursor. Deallocation frees everything at once.

```
Memory: [████████████░░░░░░░░░░░░░░░░]
                     ^ cursor

alloc(100): cursor += 100
alloc(50):  cursor += 50
reset():    cursor = 0  (everything freed instantly)
```

**Use for**: per-frame temporary allocations, string building, scratch computations.

```zig
pub const Arena = struct {
    buffer: []u8,
    offset: usize,

    pub fn init(buffer: []u8) Arena {
        return .{ .buffer = buffer, .offset = 0 };
    }

    pub fn alloc(self: *Arena, comptime T: type, count: usize) ![]T {
        const byte_count = count * @sizeOf(T);
        const alignment = @alignOf(T);
        const aligned_offset = std.mem.alignForward(usize, self.offset, alignment);

        if (aligned_offset + byte_count > self.buffer.len) return error.OutOfMemory;

        const result = @as([*]T, @ptrCast(@alignCast(self.buffer[aligned_offset..].ptr)))[0..count];
        self.offset = aligned_offset + byte_count;
        return result;
    }

    pub fn reset(self: *Arena) void {
        self.offset = 0;
    }

    // Implement std.mem.Allocator interface so it works with std library
    pub fn allocator(self: *Arena) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = arenaAlloc,
                .resize = arenaResize,
                .free = arenaFree,
            },
        };
    }
};
```

### Pool Allocator

A pool allocates fixed-size blocks. Free blocks form a **free list** (a linked list embedded in the free blocks themselves — no extra memory needed).

```
Pool of 64-byte blocks:
[used][FREE → ][used][FREE → ][FREE → null][used]
```

**Use for**: entities, components, particles — anything where you allocate/free lots of same-sized objects.

```zig
pub fn Pool(comptime T: type) type {
    return struct {
        const Node = struct { next: ?*Node };

        buffer: []u8,
        free_list: ?*Node,

        pub fn init(buffer: []u8) @This() {
            var self: @This() = .{ .buffer = buffer, .free_list = null };
            // Initialize free list by chaining all blocks
            const block_size = @max(@sizeOf(T), @sizeOf(Node));
            var i: usize = 0;
            while (i + block_size <= buffer.len) : (i += block_size) {
                const node: *Node = @ptrCast(@alignCast(buffer[i..].ptr));
                node.next = self.free_list;
                self.free_list = node;
            }
            return self;
        }

        pub fn alloc(self: *@This()) ?*T {
            const node = self.free_list orelse return null;
            self.free_list = node.next;
            return @ptrCast(@alignCast(node));
        }

        pub fn free(self: *@This(), ptr: *T) void {
            const node: *Node = @ptrCast(@alignCast(ptr));
            node.next = self.free_list;
            self.free_list = node;
        }
    };
}
```

### Frame Allocator Pattern

Common pattern in game engines: two arenas, swapped each frame.

```
Frame N:   Arena A is current (allocate here), Arena B was previous (read-only)
Frame N+1: Arena B is current, Arena A is reset and becomes scratch
```

This lets you keep data alive for exactly one frame without per-object freeing.

### Zig-Specific Tips

- Implement the `std.mem.Allocator` interface so your allocators work with `std.ArrayList`, `std.HashMap`, etc.
- Use `@alignCast` and `@ptrCast` when converting between `[]u8` and typed pointers
- Use `std.mem.alignForward` to handle alignment
- Zig's `std.heap.ArenaAllocator` exists but wraps a backing allocator with linked-list chunks — your fixed-buffer arena is faster for known-size scenarios

---

## 5. Platform Layer (Window & Input)

### What the Platform Layer Does

The platform layer is the **boundary between your engine and the OS**. It handles:
- Creating a window
- Processing input events (keyboard, mouse)
- Getting the current time
- Creating a rendering surface (Metal layer, Vulkan surface)

### Architecture

Abstract the OS behind a uniform interface:

```zig
pub const Platform = struct {
    // Function pointers or tagged union — your choice
    pub const Event = union(enum) {
        key_down: Key,
        key_up: Key,
        mouse_move: struct { x: f32, y: f32 },
        mouse_button_down: MouseButton,
        mouse_button_up: MouseButton,
        window_resize: struct { width: u32, height: u32 },
        window_close: void,
    };

    pub fn init(width: u32, height: u32, title: []const u8) !Platform { ... }
    pub fn pollEvents(self: *Platform) ?Event { ... }
    pub fn getTime() f64 { ... }
    pub fn swapBuffers(self: *Platform) void { ... }
    pub fn deinit(self: *Platform) void { ... }
};
```

### macOS (Cocoa / AppKit)

On macOS you talk to the Objective-C runtime. Zig can call C functions directly, and Objective-C is just C with message passing.

Key steps:
1. **`objc_msgSend`**: All Objective-C calls go through this function. Import it from `/usr/lib/libobjc.dylib`.
2. **Create `NSApplication`**: The app singleton.
3. **Create `NSWindow`**: Specifies size, style, title.
4. **Create `CAMetalLayer`** or `NSOpenGLView`: The rendering surface.
5. **Run the event loop**: Call `[NSApp nextEventMatchingMask:...]` to poll events.

```zig
// Zig calling Objective-C runtime
const objc = @cImport({
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
});

// objc_msgSend with appropriate type cast
fn msgSend(target: anytype, sel: objc.SEL, args: anytype) callconv(.C) anytype { ... }
```

This is the hardest part of the platform layer. Take it step by step:
1. First, just open a window with a solid color
2. Then add keyboard input
3. Then add mouse input
4. Then add the Metal rendering surface

### Linux (X11 / Xcb)

X11 is a C library. Zig calls it directly:
1. `XOpenDisplay` — connect to X server
2. `XCreateWindow` — create window
3. `XNextEvent` / `XPending` — poll events
4. For Vulkan: `vkCreateXlibSurfaceKHR`

### Windows (Win32)

Win32 is also C:
1. `RegisterClassW` + `CreateWindowExW` — create window
2. `PeekMessageW` + `DispatchMessageW` — event loop
3. `WndProc` callback — handles `WM_KEYDOWN`, `WM_MOUSEMOVE`, etc.

### Input System

Layer your input system:
1. **Raw events**: OS-specific keycodes → engine `Key` enum
2. **Input state**: Array of booleans, one per key. Updated each frame.
3. **Queries**: `isKeyDown(key)`, `isKeyPressed(key)` (just went down this frame), `isKeyReleased(key)`

```zig
pub const Input = struct {
    current: [256]bool = [_]bool{false} ** 256,
    previous: [256]bool = [_]bool{false} ** 256,

    pub fn update(self: *Input) void {
        self.previous = self.current;
    }

    pub fn setKey(self: *Input, key: u8, down: bool) void {
        self.current[key] = down;
    }

    pub fn isDown(self: Input, key: u8) bool {
        return self.current[key];
    }

    pub fn justPressed(self: Input, key: u8) bool {
        return self.current[key] and !self.previous[key];
    }

    pub fn justReleased(self: Input, key: u8) bool {
        return !self.current[key] and self.previous[key];
    }
};
```

---

## 6. Software Rasterizer

### Why Start with Software Rendering

Before touching GPU APIs, build a software rasterizer. This teaches you:
- How triangles become pixels
- The rendering pipeline stages
- Depth buffering
- Texture mapping
- What GPU hardware actually automates

### The Rendering Pipeline

```
3D Vertices → [Model Transform] → World Space
            → [View Transform]  → Camera Space
            → [Projection]      → Clip Space
            → [Perspective Divide] → NDC (-1 to 1)
            → [Viewport Transform] → Screen Space (pixels)
            → [Rasterization]   → Fragments (pixels)
            → [Fragment Processing] → Final color
            → [Depth Test]      → Framebuffer
```

### Framebuffer

A 2D array of pixels. Each pixel has color (RGBA) and depth (float).

```zig
pub const Framebuffer = struct {
    width: u32,
    height: u32,
    color: []u32,  // ARGB packed
    depth: []f32,  // depth per pixel, initialized to 1.0 (far)

    pub fn clear(self: *Framebuffer, color: u32) void {
        @memset(self.color, color);
        @memset(self.depth, 1.0);
    }

    pub fn setPixel(self: *Framebuffer, x: u32, y: u32, color: u32, z: f32) void {
        const idx = y * self.width + x;
        if (z < self.depth[idx]) {  // depth test
            self.depth[idx] = z;
            self.color[idx] = color;
        }
    }
};
```

### Triangle Rasterization

The core algorithm: given 3 screen-space vertices, fill in all the pixels inside the triangle.

**Edge function method** (the modern approach, GPU-friendly):

For a triangle with vertices v0, v1, v2, a point P is inside if all three edge functions are positive:

```
edge(v0, v1, P) = (v1.x - v0.x) * (P.y - v0.y) - (v1.y - v0.y) * (P.x - v0.x)
```

The three edge values also give you **barycentric coordinates** (u, v, w) which you use to interpolate vertex attributes (color, texture coords, depth).

```zig
pub fn drawTriangle(fb: *Framebuffer, v0: Vertex, v1: Vertex, v2: Vertex) void {
    // Compute bounding box (clipped to screen)
    const min_x = @max(0, @min(v0.x, @min(v1.x, v2.x)));
    const max_x = @min(fb.width - 1, @max(v0.x, @max(v1.x, v2.x)));
    const min_y = @max(0, @min(v0.y, @min(v1.y, v2.y)));
    const max_y = @min(fb.height - 1, @max(v0.y, @max(v1.y, v2.y)));

    const area = edgeFunction(v0, v1, v2);

    // Iterate over bounding box
    var y = min_y;
    while (y <= max_y) : (y += 1) {
        var x = min_x;
        while (x <= max_x) : (x += 1) {
            const p = .{ .x = x + 0.5, .y = y + 0.5 };
            const w0 = edgeFunction(v1, v2, p);
            const w1 = edgeFunction(v2, v0, p);
            const w2 = edgeFunction(v0, v1, p);

            if (w0 >= 0 and w1 >= 0 and w2 >= 0) {
                // Barycentric interpolation
                const u = w0 / area;
                const v = w1 / area;
                const w = w2 / area;

                // Interpolate depth
                const z = u * v0.z + v * v1.z + w * v2.z;

                // Interpolate color (or texture coords)
                const color = interpolateColor(v0.color, v1.color, v2.color, u, v, w);

                fb.setPixel(@intFromFloat(x), @intFromFloat(y), color, z);
            }
        }
    }
}
```

### Perspective-Correct Interpolation

Barycentric interpolation in screen space is incorrect for perspective projection. You must divide attributes by `w` (the clip-space w), interpolate, then multiply back:

```
attr_screen = attr / w
interpolated = u * attr0_screen + v * attr1_screen + w * attr2_screen
one_over_w = u * (1/w0) + v * (1/w1) + w * (1/w2)
attr_correct = interpolated / one_over_w
```

This is critical for texture mapping to look correct.

### Optimizations with SIMD

- Process 4 or 8 pixels at once using `@Vector(4, f32)` for edge function evaluation
- Use `@Vector` comparisons to create a mask of which pixels are inside the triangle
- Compute edge functions incrementally (add a constant when moving +1 in x or y)

### Textures

A texture is a 2D array of colors. To sample it:
1. Map the triangle's UV coordinates (0..1) to pixel coordinates in the texture
2. Use **nearest-neighbor** (fast, pixelated) or **bilinear** (smooth) sampling

```zig
pub fn sampleNearest(texture: Texture, u: f32, v: f32) u32 {
    const x = @intFromFloat(u * @as(f32, @floatFromInt(texture.width - 1)));
    const y = @intFromFloat(v * @as(f32, @floatFromInt(texture.height - 1)));
    return texture.pixels[y * texture.width + x];
}
```

### Line Drawing (Bresenham's Algorithm)

Useful for wireframe and debug rendering:

```
// For each pixel along the line from (x0,y0) to (x1,y1):
dx = abs(x1 - x0), dy = -abs(y1 - y0)
sx = if x0 < x1 then 1 else -1
sy = if y0 < y1 then 1 else -1
error = dx + dy

loop:
    plot(x0, y0)
    if x0 == x1 and y0 == y1: break
    e2 = 2 * error
    if e2 >= dy: error += dy; x0 += sx
    if e2 <= dx: error += dx; y0 += sy
```

---

## 7. GPU Rendering (Metal / Vulkan)

### When to Move to GPU

Once your software rasterizer works (can draw textured, lit triangles with depth testing), you understand the pipeline. Now replicate it on the GPU for 1000x performance.

### Metal (macOS)

Metal is Apple's GPU API. It's simpler than Vulkan.

**Core concepts**:
- **Device** (`MTLDevice`): Represents the GPU
- **Command Queue**: Submits work to the GPU
- **Command Buffer**: A batch of GPU commands
- **Render Pipeline State**: Compiled shaders + blend/depth config
- **Buffers**: Vertex data, uniforms (uploaded to GPU memory)
- **Textures**: Image data on the GPU
- **Render Pass Descriptor**: Describes what to render to (the drawable)

**Render loop**:
1. Get the next drawable from the `CAMetalLayer`
2. Create a command buffer
3. Create a render command encoder with the render pass descriptor
4. Set pipeline state, vertex buffers, uniforms
5. Draw primitives
6. End encoding
7. Present the drawable
8. Commit the command buffer

**Shaders**: Written in Metal Shading Language (MSL) — a C++-like language. You'll write:
- **Vertex shader**: Transforms vertices (model → clip space)
- **Fragment shader**: Computes pixel color

Zig integration: Metal is Objective-C, so you use `objc_msgSend` like the platform layer. The shader code is separate `.metal` files compiled by Xcode's tools or `xcrun metal`.

### Vulkan (Linux / Windows / macOS via MoltenVK)

Vulkan is more verbose but cross-platform. Key concepts are similar but more explicit:
- **Instance, Physical Device, Logical Device**: GPU setup
- **Swap Chain**: Double/triple buffering
- **Render Pass, Framebuffer**: Describe render targets
- **Graphics Pipeline**: Shaders + fixed-function state (very explicit)
- **Command Pool, Command Buffer**: GPU command recording
- **Synchronization**: Semaphores, fences (you manage all synchronization)
- **Descriptor Sets**: How shaders access buffers/textures

**Shaders**: Written in GLSL, compiled to SPIR-V binary format.

### Recommended Path

1. **Start with Metal on macOS** — it's the simplest modern GPU API
2. Once that works, add Vulkan for Linux/Windows
3. Abstract both behind a render backend interface:

```zig
pub const RenderBackend = struct {
    createBuffer: *const fn (data: []const u8) Buffer,
    createTexture: *const fn (width: u32, height: u32, pixels: []const u32) Texture,
    beginFrame: *const fn () void,
    draw: *const fn (mesh: Mesh, material: Material, transform: Mat4) void,
    endFrame: *const fn () void,
};
```

---

## 8. Entity-Component-System (ECS)

### What is ECS

Traditional OOP: `class Player extends Entity { position, health, sprite, ... }`

ECS splits this into three concepts:
- **Entity**: Just an ID (integer). No data, no behavior.
- **Component**: Pure data attached to an entity. `Position { x, y, z }`, `Health { hp, max_hp }`, `Sprite { texture_id }`.
- **System**: Logic that operates on entities with specific components. "Move all entities that have Position + Velocity".

### Why ECS

1. **Cache performance**: Components stored in contiguous arrays (SoA — Structure of Arrays). When a system iterates `Position` components, they're all packed together in memory → fast cache lines.
2. **Composition over inheritance**: Build entities by mixing components. A "bullet" is `Position + Velocity + Damage`. A "tree" is `Position + Sprite`. No class hierarchy.
3. **Parallelism**: Systems that touch different components can run in parallel.

### Data Layout: SoA vs AoS

```
AoS (Array of Structs) — bad for cache:
[{pos, vel, hp}, {pos, vel, hp}, {pos, vel, hp}, ...]

SoA (Structure of Arrays) — good for cache:
positions: [pos, pos, pos, ...]
velocities: [vel, vel, vel, ...]
healths: [hp, hp, hp, ...]
```

When the physics system iterates positions and velocities, it touches **only** those arrays — no cache pollution from health data.

### Archetype-Based ECS

Group entities by their component set (archetype). All entities with `{Position, Velocity}` are stored together. All entities with `{Position, Velocity, Health}` are stored together.

```zig
const Archetype = struct {
    // Component type IDs this archetype has
    component_types: []const TypeId,
    // Parallel arrays of component data, one per component type
    columns: []Column,
    // Number of entities in this archetype
    count: usize,
};

const Column = struct {
    // Raw bytes, interpreted as []T based on component type
    data: []u8,
    elem_size: usize,
};
```

### Simple Implementation Approach

Start simple — you can optimize later:

```zig
pub const World = struct {
    next_entity: u32 = 0,
    // For each component type, a HashMap from entity ID to component data
    positions: std.AutoHashMap(u32, Position),
    velocities: std.AutoHashMap(u32, Velocity),
    sprites: std.AutoHashMap(u32, Sprite),
    // ... add more as needed

    pub fn spawn(self: *World) u32 {
        const id = self.next_entity;
        self.next_entity += 1;
        return id;
    }

    pub fn addPosition(self: *World, entity: u32, pos: Position) void {
        self.positions.put(entity, pos);
    }
};
```

Start with this hash-map approach. Profile. Then move to archetype SoA when you need the performance.

### Zig Comptime ECS

Zig's `comptime` can generate component storage and query iterators at compile time:

```zig
// Hypothetical: define your world's component types at comptime
const MyWorld = ecs.World(.{ Position, Velocity, Health, Sprite });

// Query: iterate all entities with Position AND Velocity
var iter = world.query(.{ Position, Velocity });
while (iter.next()) |row| {
    row.position.* = row.position.add(row.velocity.scale(dt));
}
```

This is advanced but very powerful — the query iterator is specialized at compile time with zero runtime type checking.

---

## 9. Physics Engine

### Overview

A physics engine does two things:
1. **Collision detection**: Which objects are overlapping?
2. **Collision response / dynamics**: How do they react? (bounce, stop, slide)

### Collision Detection

#### Broad Phase: Spatial Partitioning

Testing every object against every other object is O(n^2). The broad phase quickly eliminates pairs that can't possibly collide.

**Grid**: Divide the world into cells. Only test objects in the same or adjacent cells.

```
┌───┬───┬───┬───┐
│ A │   │   │   │
├───┼───┼───┼───┤
│   │AB │ B │   │  A and B are in adjacent cells → test them
├───┼───┼───┼───┤
│   │   │   │ C │  C is far away → skip
├───┼───┼───┼───┤
│   │   │   │   │
└───┴───┴───┴───┘
```

**AABB (Axis-Aligned Bounding Box)**: A simple rectangle/box aligned to axes. Fast overlap test:

```zig
pub fn aabbOverlap(a: AABB, b: AABB) bool {
    return a.min.v[0] <= b.max.v[0] and a.max.v[0] >= b.min.v[0]
       and a.min.v[1] <= b.max.v[1] and a.max.v[1] >= b.min.v[1]
       and a.min.v[2] <= b.max.v[2] and a.max.v[2] >= b.min.v[2];
}
```

#### Narrow Phase: Exact Collision

**Sphere-Sphere**: `distance(center_a, center_b) < radius_a + radius_b`

**SAT (Separating Axis Theorem)**: For convex shapes, if you can find an axis where the projections don't overlap, the shapes don't collide. Test all face normals of both shapes as potential separating axes.

**GJK (Gilbert-Johnson-Keerthi)**: A more general algorithm for convex shapes. Uses the Minkowski difference and iteratively builds a simplex. More complex but handles arbitrary convex shapes.

Start with AABB and sphere collisions. Add SAT for OBB (Oriented Bounding Box) later.

### Collision Response

When two objects collide, compute:
1. **Contact normal**: The direction of separation
2. **Penetration depth**: How far they overlap
3. **Impulse**: How much to push them apart

**Basic impulse resolution** (for two rigid bodies):

```
relative_velocity = velocity_b - velocity_a
velocity_along_normal = dot(relative_velocity, normal)

// Don't resolve if objects are separating
if velocity_along_normal > 0: return

// Coefficient of restitution (bounciness, 0..1)
e = min(restitution_a, restitution_b)

// Impulse magnitude
j = -(1 + e) * velocity_along_normal
j = j / (1/mass_a + 1/mass_b)

// Apply impulse
velocity_a -= (j / mass_a) * normal
velocity_b += (j / mass_b) * normal
```

### Rigid Body Dynamics

Each rigid body has:

```zig
pub const RigidBody = struct {
    position: Vec4,
    velocity: Vec4,
    acceleration: Vec4,
    mass: f32,
    inv_mass: f32,  // 1/mass, 0 for static objects
    restitution: f32,  // bounciness
    friction: f32,
};
```

**Integration** (update each frame):

```zig
pub fn integrate(body: *RigidBody, dt: f32) void {
    if (body.inv_mass == 0) return;  // static

    // Semi-implicit Euler (better than basic Euler)
    body.velocity = body.velocity.add(body.acceleration.scale(dt));
    body.position = body.position.add(body.velocity.scale(dt));
}
```

**Integration methods** ranked by accuracy:
1. Explicit Euler — simplest, least stable
2. Semi-implicit Euler — simple, good enough for games
3. Verlet — good for constraints (cloth, ropes)
4. RK4 — very accurate, expensive, overkill for most games

### SIMD in Physics

- AABB overlap: test all 3 axes simultaneously with `@Vector(4, f32)` comparisons
- Batch impulse resolution: process 4 collision pairs at once
- Spatial grid lookups: vectorized cell index computation

---

## 10. Audio Engine

### Concepts

Digital audio is a stream of **samples** — numbers representing air pressure at regular intervals.
- **Sample rate**: 44100 Hz (CD quality) = 44100 samples per second
- **Bit depth**: 16-bit (integer) or 32-bit (float) per sample
- **Channels**: 1 (mono), 2 (stereo)

### Audio Mixing

Playing multiple sounds = adding their samples together:

```zig
pub fn mix(output: []f32, sources: []const []const f32) void {
    @memset(output, 0);
    for (sources) |source| {
        for (output, 0..) |*out, i| {
            if (i < source.len) {
                out.* += source[i];
            }
        }
    }
    // Clamp to prevent clipping
    for (output) |*sample| {
        sample.* = std.math.clamp(sample.*, -1.0, 1.0);
    }
}
```

### Platform Audio Output

- **macOS**: Core Audio (`AudioQueueNewOutput` or `AudioUnit`)
- **Linux**: ALSA (`snd_pcm_open`, `snd_pcm_writei`)
- **Windows**: WASAPI (`IAudioClient`, `IAudioRenderClient`)

All three use a **callback model**: the OS calls your function when it needs more audio data. You fill a buffer with mixed samples.

### Sound System Design

```zig
pub const Sound = struct {
    samples: []const f32,  // PCM data
    sample_rate: u32,
};

pub const PlayingSound = struct {
    sound: *const Sound,
    position: usize,  // current playback position (in samples)
    volume: f32,
    looping: bool,
    playing: bool,
};

pub const AudioMixer = struct {
    playing: [MAX_SOUNDS]PlayingSound,
    active_count: u32,

    pub fn play(self: *AudioMixer, sound: *const Sound, volume: f32, loop: bool) void { ... }

    // Called by the OS audio callback
    pub fn fillBuffer(self: *AudioMixer, output: []f32) void {
        @memset(output, 0);
        for (self.playing[0..self.active_count]) |*ps| {
            if (!ps.playing) continue;
            for (output, 0..) |*out, i| {
                out.* += ps.sound.samples[ps.position] * ps.volume;
                ps.position += 1;
                if (ps.position >= ps.sound.samples.len) {
                    if (ps.looping) ps.position = 0 else { ps.playing = false; break; }
                }
            }
        }
    }
};
```

### Spatial Audio (3D)

For 3D sound positioning:
- **Attenuation**: Volume decreases with distance: `volume = 1.0 / (distance * distance)`
- **Panning**: Left/right based on angle to listener: `left = cos(angle) * volume`, `right = sin(angle) * volume`

SIMD: mix 4 samples at once with `@Vector(4, f32)`.

---

## 11. Asset Pipeline

### File Formats to Implement (Start Simple)

| Asset Type | Simple Format | Description |
|-----------|--------------|-------------|
| Image | BMP | Uncompressed, trivial header parsing |
| Image | TGA | Slightly more features, still simple |
| 3D Mesh | OBJ | Text-based, easy to parse |
| Audio | WAV | Uncompressed PCM with a simple header |
| Font | BMFont | Pre-rasterized bitmap font (text descriptor + image) |

### BMP Loader

BMP files have a 54-byte header, then raw pixel data:

```
Bytes 0-1:   "BM" magic
Bytes 2-5:   file size
Bytes 10-13: pixel data offset
Bytes 14-17: header size (40)
Bytes 18-21: width
Bytes 22-25: height
Bytes 28-29: bits per pixel (24 or 32)
```

```zig
pub fn loadBMP(data: []const u8) !Image {
    if (data.len < 54) return error.InvalidBMP;
    if (data[0] != 'B' or data[1] != 'M') return error.InvalidBMP;

    const offset = std.mem.readInt(u32, data[10..14], .little);
    const width = std.mem.readInt(u32, data[18..22], .little);
    const height = std.mem.readInt(u32, data[22..26], .little);
    const bpp = std.mem.readInt(u16, data[28..30], .little);

    // Parse pixel data (note: BMP is bottom-up, BGR order)
    ...
}
```

### OBJ Loader

OBJ is a text format:

```
v 1.0 2.0 3.0        # vertex position
vt 0.5 0.5           # texture coordinate
vn 0.0 1.0 0.0       # vertex normal
f 1/1/1 2/2/2 3/3/3  # face (indices into v/vt/vn)
```

Parse line by line. Build vertex and index arrays.

### WAV Loader

WAV has a RIFF header:

```
Bytes 0-3:   "RIFF"
Bytes 8-11:  "WAVE"
Bytes 12-15: "fmt " (format chunk)
Bytes 20-21: format (1 = PCM)
Bytes 22-23: channels
Bytes 24-27: sample rate
Bytes 34-35: bits per sample
Then find "data" chunk: raw PCM samples follow
```

### Asset Manager

```zig
pub const AssetManager = struct {
    allocator: std.mem.Allocator,
    textures: std.StringHashMap(Texture),
    meshes: std.StringHashMap(Mesh),
    sounds: std.StringHashMap(Sound),

    pub fn loadTexture(self: *AssetManager, path: []const u8) !*Texture { ... }
    pub fn getMesh(self: *AssetManager, name: []const u8) ?*Mesh { ... }
};
```

---

## 12. Scene Graph & Cameras

### Scene Graph

A tree structure where each node has a **local transform** (relative to parent) and a computed **world transform**.

```
World
├── Player (pos: 0,0,0)
│   ├── Sword (pos: 1,0,0 relative to player → world: 1,0,0)
│   └── Shield (pos: -1,0,0 relative to player → world: -1,0,0)
├── Enemy (pos: 10,0,5)
└── Tree (pos: -3,0,2)
```

```zig
pub const SceneNode = struct {
    local_transform: Mat4,
    world_transform: Mat4,
    parent: ?*SceneNode,
    children: std.ArrayList(*SceneNode),
    entity: ?EntityId,  // link to ECS entity

    pub fn updateWorldTransform(self: *SceneNode) void {
        if (self.parent) |parent| {
            self.world_transform = parent.world_transform.mul(self.local_transform);
        } else {
            self.world_transform = self.local_transform;
        }
        for (self.children.items) |child| {
            child.updateWorldTransform();
        }
    }
};
```

### Camera

A camera is defined by:
- **Position** and **orientation** (or look-at target)
- **Projection** (perspective or orthographic)

The camera produces two matrices:
1. **View matrix**: `lookAt(eye, target, up)` — transforms world to camera space
2. **Projection matrix**: `perspective(fov, aspect, near, far)` — transforms camera space to clip space

Combined: `MVP = projection * view * model`

```zig
pub const Camera = struct {
    position: Vec4,
    target: Vec4,
    up: Vec4,
    fov: f32,        // field of view in radians
    aspect: f32,     // width / height
    near: f32,
    far: f32,

    pub fn viewMatrix(self: Camera) Mat4 {
        return Mat4.lookAt(self.position, self.target, self.up);
    }

    pub fn projectionMatrix(self: Camera) Mat4 {
        return Mat4.perspective(self.fov, self.aspect, self.near, self.far);
    }

    pub fn viewProjection(self: Camera) Mat4 {
        return self.projectionMatrix().mul(self.viewMatrix());
    }
};
```

### Frustum Culling

The view frustum is the visible volume (a truncated pyramid). Don't render objects outside it.

Extract 6 planes from the view-projection matrix, then test each object's AABB against all 6 planes. If the AABB is entirely behind any plane, skip it.

---

## 13. Suggested Build Order

Build in this exact order. Each step is testable on its own.

### Phase 1: Foundation (Week 1-2)

1. **Math library** — Vec4, Mat4, Quat with `@Vector`. Write exhaustive tests.
2. **Arena allocator** — Simple bump allocator with `std.mem.Allocator` interface.

**Milestone**: All math tests pass. You can multiply matrices, normalize vectors, convert quaternions.

### Phase 2: See Something (Week 3-4)

3. **Platform layer** — Open a window on your OS. Handle close event.
4. **Software rasterizer** — Clear screen to a color. Draw a 2D triangle. Display in window.
5. **Input** — Handle keyboard and mouse events.

**Milestone**: A colored triangle on screen. Press ESC to close.

### Phase 3: 3D (Week 5-7)

6. **3D pipeline** — Vertex transformation through MVP matrix. Depth buffer.
7. **Camera** — Free-look camera with WASD + mouse.
8. **OBJ loader** — Load a simple mesh.
9. **Textures** — BMP loader + textured triangles.

**Milestone**: A textured 3D model you can fly around with the camera.

### Phase 4: GPU (Week 8-10)

10. **Metal backend** (macOS) — Replicate the software rasterizer's output on the GPU.
11. **Shaders** — Vertex + fragment shaders in MSL.
12. **Lighting** — Phong shading (ambient + diffuse + specular).

**Milestone**: GPU-rendered lit scene matching the software rasterizer output.

### Phase 5: Systems (Week 11-14)

13. **ECS** — Simple hash-map based. Spawn entities with components.
14. **Physics** — AABB collision detection + impulse response.
15. **Audio** — WAV loader + audio mixer with platform output.
16. **Scene graph** — Transform hierarchy.

**Milestone**: Objects collide, sounds play, entities are managed by ECS.

### Phase 6: Polish (Week 15+)

17. **Pool allocator** — For ECS components and particles.
18. **Frustum culling** — Skip off-screen objects.
19. **Particle system** — Smoke, fire, sparks.
20. **Debug rendering** — Wireframe AABBs, grid, axes.
21. **Profiling** — Frame time breakdown, memory usage display.

---

## Appendix A: Key Algorithms Reference

| Algorithm | Used For | Complexity |
|-----------|---------|------------|
| Edge function rasterization | Triangle filling | O(pixels in bbox) |
| Bresenham's line | Line drawing | O(max(dx,dy)) |
| Barycentric interpolation | Attribute interpolation | O(1) per pixel |
| SAT (Separating Axis Theorem) | Convex collision | O(faces * axes) |
| GJK | General convex collision | O(iterations) |
| Semi-implicit Euler | Physics integration | O(1) per body |
| Frustum culling | Visibility | O(objects) |
| Spatial hash grid | Broad-phase collision | O(1) average lookup |

## Appendix B: Zig SIMD Cheat Sheet

```zig
// Declare a 4-wide float vector
const V4 = @Vector(4, f32);

// Arithmetic (maps to single SIMD instructions)
const sum = a + b;
const diff = a - b;
const prod = a * b;
const quot = a / b;

// Broadcast a scalar to all lanes
const splat: V4 = @splat(3.14);

// Horizontal reduction
const dot = @reduce(.Add, a * b);   // dot product
const min_val = @reduce(.Min, a);   // minimum element
const max_val = @reduce(.Max, a);   // maximum element

// Shuffle / swizzle
const yzxw = @shuffle(f32, v, undefined, [4]i32{ 1, 2, 0, 3 });

// Comparison (returns @Vector(4, bool))
const mask = a > b;

// Select based on mask
const result = @select(f32, mask, a, b);

// Square root
const sqrt = @sqrt(a);

// Abs
const abs_v = @abs(a);

// Min / Max (per-element)
const min_v = @min(a, b);
const max_v = @max(a, b);
```

## Appendix C: Resources

These are concepts to search for when you get stuck — not library dependencies:

- **"Fix Your Timestep" by Glenn Fiedler** — the definitive game loop article
- **"Scratchapixel"** — software rendering tutorials (translate C++ concepts to Zig)
- **"Real-Time Collision Detection" by Ericson** — the collision detection bible
- **"Game Engine Architecture" by Jason Gregory** — comprehensive reference
- **Metal Programming Guide** (Apple developer docs) — official Metal reference
- **Vulkan Tutorial (vulkan-tutorial.com)** — step-by-step Vulkan
- **"Handmade Hero" by Casey Muratori** — building a game engine from scratch in C (similar philosophy to what you're doing in Zig)

---

*This guide is your roadmap. Build each piece, test it, understand it, then move on. The engine grows organically from the bottom up. Every line of code is yours.*
