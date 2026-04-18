# zreal — One Week Build Plan

Build a working game engine and a playable demo in 7 days. Each day has clear deliverables and a "done when" checkpoint. The demo target: a simple 3D scene where you can move a player, collide with objects, and see textured geometry — running natively on macOS.

> **Scope rule**: If something takes longer than expected, cut scope on that task and move forward. A running demo with fewer features beats a perfect engine that never runs.

---

## Day 1 (Mon): Math + Memory Foundation

**Goal**: A fully tested SIMD math library and custom allocators.

### Tasks

- [ ] **1.1** Create `src/math/vec.zig` — `Vec2`, `Vec3`, `Vec4` backed by `@Vector(4, f32)`
  - `add`, `sub`, `scale`, `dot`, `cross`, `length`, `normalize`
  - Component accessors: `x()`, `y()`, `z()`, `w()`
  - See guide: [Chapter 3 — Math Library](game-engine-guide.md#3-math-library-simd)

- [ ] **1.2** Create `src/math/mat.zig` — `Mat4` (column-major)
  - `identity`, `mul` (mat*mat), `mulVec` (mat*vec)
  - `translation()`, `scaling()`, `rotationX/Y/Z()`
  - `lookAt()`, `perspective()` 
  - `transpose()`, `inverse()` (inverse can be simplified — use cofactor for 4x4)
  - See guide: [Chapter 3 — Mat4 section](game-engine-guide.md#mat4-44-matrix)

- [ ] **1.3** Create `src/math/quat.zig` — `Quat`
  - `fromAxisAngle()`, `mul()`, `conjugate()`, `normalize()`, `toMat4()`, `slerp()`
  - See guide: [Chapter 3 — Quaternions](game-engine-guide.md#quaternions)

- [ ] **1.4** Create `src/memory/arena.zig` — Arena allocator
  - Bump allocation on a fixed buffer
  - Implement `std.mem.Allocator` interface
  - `reset()` for per-frame clearing
  - See guide: [Chapter 4 — Arena Allocator](game-engine-guide.md#arena-allocator)

- [ ] **1.5** Create `src/memory/pool.zig` — Pool allocator
  - Fixed-size block allocation with embedded free list
  - See guide: [Chapter 4 — Pool Allocator](game-engine-guide.md#pool-allocator)

- [ ] **1.6** Write tests for everything above
  - Vec: dot, cross, normalize, length
  - Mat: identity * v == v, inverse(m) * m ≈ identity
  - Quat: fromAxisAngle round-trip, mul associativity
  - Arena: alloc, reset, alloc again
  - Pool: alloc, free, reuse

### Done when
```bash
zig build test   # all tests pass
```

---

## Day 2 (Tue): Platform Layer — Window + Input

**Goal**: A native window opens on macOS with keyboard/mouse input.

### Tasks

- [ ] **2.1** Create `src/platform/macos.zig` — macOS window via Objective-C runtime
  - Import `objc_msgSend` from `libobjc`
  - Create `NSApplication`, `NSWindow`
  - Set window title, size, and make it visible
  - See guide: [Chapter 5 — macOS (Cocoa)](game-engine-guide.md#macos-cocoa--appkit)

- [ ] **2.2** Create `src/platform/platform.zig` — cross-platform interface
  - `Platform.init(width, height, title)` → opens window
  - `Platform.pollEvents()` → returns `Event` union (key_down, key_up, mouse_move, window_close, window_resize)
  - `Platform.shouldClose()` → bool
  - `Platform.deinit()`

- [ ] **2.3** Create `src/platform/input.zig` — input state tracker
  - `current[256]` and `previous[256]` bool arrays
  - `isDown(key)`, `justPressed(key)`, `justReleased(key)`
  - `update()` — copies current to previous each frame
  - See guide: [Chapter 5 — Input System](game-engine-guide.md#input-system)

- [ ] **2.4** Hook up `src/main.zig` — basic game loop
  - Open window → poll events → close on ESC or window close
  - Print key presses to debug output to verify input works

### Done when
- A window opens with a title bar
- ESC closes it
- Key presses print to terminal

---

## Day 3 (Wed): Software Rasterizer

**Goal**: Render colored and textured triangles to the window.

### Tasks

- [ ] **3.1** Create `src/renderer/framebuffer.zig`
  - `Framebuffer` struct: `color: []u32`, `depth: []f32`, `width`, `height`
  - `clear(color)` — fill color buffer, reset depth to 1.0
  - `setPixel(x, y, color, depth)` — with depth test
  - See guide: [Chapter 6 — Framebuffer](game-engine-guide.md#framebuffer)

- [ ] **3.2** Create `src/renderer/rasterizer.zig`
  - `drawTriangle(fb, v0, v1, v2)` — edge function rasterization
  - Barycentric interpolation for color
  - Depth testing per pixel
  - See guide: [Chapter 6 — Triangle Rasterization](game-engine-guide.md#triangle-rasterization)

- [ ] **3.3** Create `src/renderer/texture.zig`
  - `Texture` struct: `pixels: []u32`, `width`, `height`
  - `sampleNearest(u, v)` → u32 color
  - `sampleBilinear(u, v)` → u32 color (stretch goal)

- [ ] **3.4** Blit framebuffer to macOS window
  - Create a `CALayer` or `NSBitmapImageRep` and copy the color buffer into it
  - Call this each frame after rendering

- [ ] **3.5** Draw a 3D scene with MVP transform
  - Apply model → view → projection → viewport pipeline
  - Draw a spinning colored cube (hardcoded vertices)
  - Use the `Mat4.perspective()` and `Mat4.lookAt()` from Day 1
  - See guide: [Chapter 6 — The Rendering Pipeline](game-engine-guide.md#the-rendering-pipeline)

### Done when
- A spinning colored cube is visible in the window
- Depth buffer works (back faces hidden)

---

## Day 4 (Thu): Camera + Asset Loading

**Goal**: Free-look camera and load external assets (meshes, textures).

### Tasks

- [ ] **4.1** Create `src/renderer/camera.zig`
  - `Camera` struct: position, yaw, pitch, fov, aspect, near, far
  - `viewMatrix()` — computed from position + yaw/pitch
  - `projectionMatrix()` — perspective
  - `viewProjection()` — combined
  - WASD movement + mouse look
  - See guide: [Chapter 12 — Camera](game-engine-guide.md#camera)

- [ ] **4.2** Create `src/assets/bmp.zig` — BMP image loader
  - Parse 24-bit and 32-bit BMP files
  - Return `Texture` struct
  - Handle bottom-up row order and BGR→RGB conversion
  - See guide: [Chapter 11 — BMP Loader](game-engine-guide.md#bmp-loader)

- [ ] **4.3** Create `src/assets/obj.zig` — OBJ mesh loader
  - Parse `v`, `vt`, `vn`, `f` lines
  - Build vertex buffer (position + texcoord + normal) and index buffer
  - Handle `f v/vt/vn` format
  - See guide: [Chapter 11 — OBJ Loader](game-engine-guide.md#obj-loader)

- [ ] **4.4** Create `src/assets/wav.zig` — WAV audio loader
  - Parse RIFF header, fmt chunk, data chunk
  - Return `Sound` struct with PCM samples as `[]f32`
  - Support 16-bit PCM mono/stereo at 44100Hz
  - See guide: [Chapter 11 — WAV Loader](game-engine-guide.md#wav-loader)

- [ ] **4.5** Update main — load and render an OBJ model with a BMP texture
  - Fly around it with the camera

### Done when
- You can load a `.obj` file and a `.bmp` texture
- The textured model renders correctly
- Camera moves with WASD + mouse

---

## Day 5 (Fri): ECS + Physics

**Goal**: Entities managed by ECS, basic collision detection and response.

### Tasks

- [ ] **5.1** Create `src/ecs/world.zig` — Entity-Component-System
  - `World` struct with `spawn() → EntityId`
  - Component storage: start with `std.AutoHashMap(EntityId, T)` per component type
  - Components to define: `Transform`, `Velocity`, `Collider`, `Renderable`
  - See guide: [Chapter 8 — Simple Implementation](game-engine-guide.md#simple-implementation-approach)

- [ ] **5.2** Create `src/ecs/systems.zig` — System functions
  - `movementSystem(world, dt)` — update Transform by Velocity
  - `renderSystem(world, camera, fb)` — draw all Renderable entities
  - Each system iterates relevant component maps

- [ ] **5.3** Create `src/physics/collision.zig`
  - `AABB` struct: min, max (Vec4)
  - `aabbOverlap(a, b) → bool`
  - `sphereOverlap(pos_a, r_a, pos_b, r_b) → bool`
  - See guide: [Chapter 9 — Collision Detection](game-engine-guide.md#collision-detection)

- [ ] **5.4** Create `src/physics/rigidbody.zig`
  - `RigidBody` struct: position, velocity, mass, inv_mass, restitution
  - `integrate(body, dt)` — semi-implicit Euler
  - `resolveCollision(a, b, normal)` — impulse-based response
  - See guide: [Chapter 9 — Rigid Body Dynamics](game-engine-guide.md#rigid-body-dynamics)

- [ ] **5.5** Create `src/physics/physics_system.zig`
  - Broad phase: check all AABB pairs (brute force is fine for < 100 objects)
  - Narrow phase: compute contact normal + penetration
  - Apply impulse response
  - Integrate all bodies

- [ ] **5.6** Wire into main
  - Spawn entities with ECS
  - Run physics + movement systems each fixed timestep
  - Render via render system

### Done when
- Objects spawn via ECS
- Boxes collide and bounce
- Physics runs at fixed timestep, rendering interpolates

---

## Day 6 (Sat): Audio + Game Loop Polish

**Goal**: Sound playback, fixed timestep, frame timing, and game loop polish.

### Tasks

- [ ] **6.1** Create `src/audio/mixer.zig`
  - `AudioMixer` struct with `playing: [MAX_SOUNDS]PlayingSound`
  - `play(sound, volume, loop)` — start a sound
  - `fillBuffer(output: []f32)` — mix all playing sounds into output buffer
  - See guide: [Chapter 10 — Audio Mixing](game-engine-guide.md#audio-mixing)

- [ ] **6.2** Create `src/audio/macos_audio.zig`
  - Core Audio output via `AudioQueueNewOutput` or `AudioUnit`
  - Callback function calls `mixer.fillBuffer()`
  - See guide: [Chapter 10 — Platform Audio Output](game-engine-guide.md#platform-audio-output)

- [ ] **6.3** Implement proper fixed timestep game loop
  - Fixed physics at 60Hz
  - Accumulator pattern with spiral-of-death clamp
  - Interpolation alpha for smooth rendering
  - See guide: [Chapter 2 — Fixed Timestep](game-engine-guide.md#fixed-timestep-with-interpolation)

- [ ] **6.4** Add frame timing / debug info
  - Measure frame time, display FPS in window title or terminal
  - Track physics update count per frame

- [ ] **6.5** Add simple lighting to the software rasterizer
  - Single directional light
  - Phong shading: ambient + diffuse (skip specular for now)
  - Need vertex normals from OBJ loader

### Done when
- Sound effects play on collision or key press
- Game loop is smooth with fixed timestep
- FPS displays
- Basic lighting on 3D objects

---

## Day 7 (Sun): Demo Game

**Goal**: Build a playable demo that showcases every system.

### Demo Concept: **"Bouncing Arena"**
A first-person scene where you walk around a small arena. Cubes spawn and bounce around with physics. Colliding with them plays a sound. A score counter tracks how many you've touched.

### Tasks

- [ ] **7.1** Create `src/game/demo.zig` — game logic
  - Arena: a flat floor with 4 walls (AABBs)
  - Player: first-person camera, WASD + mouse, collides with walls
  - Spawner: every 2 seconds, spawn a colored cube at a random position with random velocity
  - Score: increment when player AABB touches a cube AABB, remove that cube

- [ ] **7.2** Create game assets
  - Hardcode simple geometry (cubes, floor quad) if OBJ loading works, or use loaded meshes
  - Create or find a simple BMP texture (checkerboard is fine — can generate procedurally)
  - Create or find a short WAV sound effect for pickup

- [ ] **7.3** Wire everything together in `src/main.zig`
  - Init: platform → renderer → audio → ECS world → spawn arena + player
  - Loop: input → physics (fixed) → game logic → render → audio → present
  - Cleanup: deinit everything

- [ ] **7.4** Polish
  - Colored cubes (different color per cube)
  - Floor with checkerboard texture
  - Score display in window title: `"zreal — Score: 42 | FPS: 60"`
  - Gravity on cubes (accelerate downward, bounce off floor)

- [ ] **7.5** Final testing
  - Run the demo for 5+ minutes — no crashes
  - Memory: verify arena reset works, no leaks (use Zig's `GeneralPurposeAllocator` in debug mode)
  - Performance: maintain 60fps

### Done when
- The demo runs
- You can walk around, cubes bounce, sounds play, score increments
- It doesn't crash

---

## Daily Rhythm

| Time | Activity |
|------|----------|
| Morning | Read the relevant guide chapter for today's tasks |
| Morning–Afternoon | Implement + test each task |
| Evening | Wire into main.zig, verify the day's milestone |
| Before bed | Commit. Review tomorrow's tasks. |

## Cutting Scope (If Behind)

If you fall behind, cut in this order (least to most critical):

1. **Cut first**: Bilinear texture sampling, spatial audio, pool allocator
2. **Simplify**: Use hardcoded geometry instead of OBJ loading
3. **Simplify**: Skip audio entirely (silent demo is still a demo)
4. **Simplify**: Skip lighting (flat-colored triangles)
5. **Never cut**: Math library, window, rasterizer, game loop, camera

The minimum viable demo is: window + input + software rasterizer + camera + hardcoded cubes + collision + game loop. Everything else is bonus.

---

## File Structure After Day 7

```
src/
├── main.zig                    # entry point, game loop, wiring
├── root.zig                    # library root
├── math/
│   ├── vec.zig                 # Vec2, Vec3, Vec4 (SIMD)
│   ├── mat.zig                 # Mat4
│   └── quat.zig                # Quaternion
├── memory/
│   ├── arena.zig               # Arena allocator
│   └── pool.zig                # Pool allocator
├── platform/
│   ├── platform.zig            # Cross-platform interface
│   ├── macos.zig               # macOS window + events
│   └── input.zig               # Input state tracking
├── renderer/
│   ├── framebuffer.zig         # Color + depth buffer
│   ├── rasterizer.zig          # Triangle rasterization
│   ├── texture.zig             # Texture sampling
│   └── camera.zig              # Camera + projection
├── ecs/
│   ├── world.zig               # Entity storage + components
│   └── systems.zig             # Movement, render systems
├── physics/
│   ├── collision.zig           # AABB, sphere overlap
│   ├── rigidbody.zig           # Rigid body + integration
│   └── physics_system.zig      # Broad/narrow phase + response
├── audio/
│   ├── mixer.zig               # Audio mixing
│   └── macos_audio.zig         # Core Audio output
├── assets/
│   ├── bmp.zig                 # BMP image loader
│   ├── obj.zig                 # OBJ mesh loader
│   └── wav.zig                 # WAV audio loader
└── game/
    └── demo.zig                # Demo game logic
```
