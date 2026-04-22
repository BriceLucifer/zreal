# zreal — One Week Build Plan

Build a working game engine and a playable demo in 7 days. Each day has clear deliverables and a "done when" checkpoint. The demo target: a simple 3D scene where you can move a player, collide with objects, and see textured geometry — **running in the browser via WASM + WebGL2**, with optional native desktop support.

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

## Day 2 (Tue): Platform Layer — WASM Bridge + Input

**Goal**: Engine runs in the browser. A canvas displays, keyboard/mouse input works via JS→WASM bridge.

### Tasks

- [ ] **2.1** Create `src/platform/web.zig` — WASM ↔ JS bridge
  - `extern "env"` declarations for JS-provided functions:
    - `jsCanvasWidth()`, `jsCanvasHeight()`
    - `jsGlClearColor(r, g, b, a)`, `jsGlClear(mask)`
    - `jsLog(ptr, len)` — for debug logging
  - `export fn` for JS to call:
    - `init()` — engine initialization
    - `update(dt: f32)` — called each frame from `requestAnimationFrame`
    - `onKeyDown(keycode: u32)`, `onKeyUp(keycode: u32)`
    - `onMouseMove(dx: f32, dy: f32)`

- [ ] **2.2** Create `src/platform/platform.zig` — comptime target switch
  ```zig
  const platform = if (@import("builtin").target.cpu.arch == .wasm32)
      @import("web.zig")
  else
      @import("native.zig");
  ```
  - Unified interface: `Platform.canvasWidth()`, `Platform.canvasHeight()`, etc.

- [ ] **2.3** Create `src/platform/input.zig` — input state tracker
  - `current[256]` and `previous[256]` bool arrays
  - `isDown(key)`, `justPressed(key)`, `justReleased(key)`
  - `update()` — copies current to previous each frame
  - On web: populated by exported `onKeyDown`/`onKeyUp`
  - See guide: [Chapter 5 — Input System](game-engine-guide.md#input-system)

- [ ] **2.4** Create `web/index.html` + `web/engine.js` — browser host
  - `index.html`: `<canvas>` element, load `engine.js`
  - `engine.js`:
    - Fetch and instantiate `.wasm` with `env` imports
    - Set up WebGL2 context on the canvas
    - Forward keyboard/mouse events to WASM exports
    - Run `requestAnimationFrame` loop calling `instance.exports.update(dt)`

- [ ] **2.5** Create `src/wasm_entry.zig` — WASM entry point
  - Imports platform/web.zig
  - Exports `init`, `update`, `onKeyDown`, `onKeyUp`, `onMouseMove`
  - Basic game loop skeleton

- [ ] **2.6** (Optional) Create `src/platform/native.zig` — native fallback
  - macOS window via Objective-C runtime (can defer to later)

### Done when
- `zig build -Dtarget=wasm32-freestanding` produces a `.wasm` file
- Opening `web/index.html` in a browser shows a colored canvas
- Key presses logged to browser console via WASM→JS debug logging

---

## Day 3 (Wed): WebGL2 Renderer

**Goal**: Render colored triangles in the browser via WebGL2.

### Tasks

- [ ] **3.1** Create `src/renderer/webgl.zig` — WebGL2 bindings via JS bridge
  - `extern "env"` for WebGL calls:
    - `jsGlCreateBuffer()`, `jsGlBindBuffer()`, `jsGlBufferData()`
    - `jsGlCreateShader()`, `jsGlShaderSource()`, `jsGlCompileShader()`
    - `jsGlCreateProgram()`, `jsGlLinkProgram()`, `jsGlUseProgram()`
    - `jsGlVertexAttribPointer()`, `jsGlEnableVertexAttribArray()`
    - `jsGlDrawArrays()`, `jsGlDrawElements()`
    - `jsGlUniformMatrix4fv()` — for passing Mat4 to shaders
  - Zig-side wrapper: `Renderer.init()`, `Renderer.clear()`, `Renderer.drawMesh()`

- [ ] **3.2** Add WebGL setup to `web/engine.js`
  - Create WebGL2 context from canvas
  - Implement all `jsGl*` functions that the WASM imports
  - Manage GL object handle mapping (WASM gets integer handles)

- [ ] **3.3** Create `src/renderer/mesh.zig`
  - `Mesh` struct: vertex data (position + color + normal), index data
  - `createCube()`, `createQuad()` — hardcoded geometry generators
  - Upload to GPU via WebGL buffer calls

- [ ] **3.4** Create shader strings (embedded in Zig via `comptime`)
  - Vertex shader: MVP transform
  - Fragment shader: vertex color output
  - Pass as string pointers to JS for `gl.shaderSource()`

- [ ] **3.5** Draw a 3D scene with MVP transform
  - Apply model → view → projection pipeline
  - Draw a spinning colored cube
  - Use `Mat4.perspective()` and `Mat4.lookAt()` from Day 1
  - Pass MVP matrix to shader via `jsGlUniformMatrix4fv()`

### Done when
- A spinning colored cube is visible in the browser canvas
- WebGL2 depth test works (back faces hidden)

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

- [ ] **4.2** Create `src/assets/obj.zig` — OBJ mesh loader
  - Parse `v`, `vt`, `vn`, `f` lines
  - Build vertex buffer (position + texcoord + normal) and index buffer
  - Handle `f v/vt/vn` format
  - On web: JS `fetch()` loads file → passes `[]u8` to WASM via shared memory
  - See guide: [Chapter 11 — OBJ Loader](game-engine-guide.md#obj-loader)

- [ ] **4.3** Create `src/assets/image.zig` — image loader (BMP or procedural)
  - Parse 24-bit/32-bit BMP or generate procedural textures (checkerboard)
  - Return `Texture` struct
  - Upload to WebGL via `jsGlTexImage2D()`

- [ ] **4.4** Add texture support to WebGL renderer
  - `jsGlCreateTexture()`, `jsGlBindTexture()`, `jsGlTexImage2D()`
  - Update fragment shader to sample texture

- [ ] **4.5** Update WASM entry — load and render an OBJ model with texture
  - Fly around it with the camera

### Done when
- A textured 3D model renders in the browser
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

- [ ] **6.2** Create audio backend via JS bridge (Web Audio API)
  - `extern "env"` for: `jsAudioPlay(sound_id, volume)`, `jsAudioStop(sound_id)`
  - JS side: `AudioContext`, decode audio buffers, play/stop
  - WAV parsing can happen in Zig or be delegated to JS `decodeAudioData()`

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
A first-person scene in the browser where you walk around a small arena. Cubes spawn and bounce around with physics. Colliding with them plays a sound. A score counter tracks how many you've touched. Press **ESC** to pause / release mouse pointer lock.

### Tasks

- [ ] **7.1** Create `src/game/demo.zig` — game logic
  - Arena: a flat floor with 4 walls (AABBs)
  - Player: first-person camera, WASD + mouse, collides with walls
  - Spawner: every 2 seconds, spawn a colored cube at a random position with random velocity
  - Score: increment when player AABB touches a cube AABB, remove that cube
  - **ESC key**: pause game / release pointer lock (important for web UX)

- [ ] **7.2** Create game assets
  - Hardcode simple geometry (cubes, floor quad) — procedural generation
  - Procedural checkerboard texture (generated in Zig, uploaded to WebGL)
  - Simple sound effect for pickup (short synthesized beep or loaded WAV)

- [ ] **7.3** Wire everything together
  - WASM entry: `export fn init()` → renderer → audio → ECS world → spawn arena + player
  - `export fn update(dt)` → input → physics (fixed) → game logic → render
  - JS side: `requestAnimationFrame` loop, pointer lock on click, ESC to unlock

- [ ] **7.4** Polish
  - Colored cubes (different color per cube)
  - Floor with checkerboard texture
  - Score + FPS display via HTML overlay (JS reads exported state from WASM)
  - Gravity on cubes (accelerate downward, bounce off floor)

- [ ] **7.5** Final testing
  - Run the demo in browser for 5+ minutes — no crashes
  - Test in Chrome + Firefox (both support WASM SIMD + WebGL2)
  - Performance: maintain 60fps
  - ESC properly releases pointer lock

### Done when
- The demo runs in the browser
- You can walk around, cubes bounce, sounds play, score increments
- ESC pauses / releases pointer lock
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

The minimum viable demo is: WASM + canvas + WebGL2 + input + camera + hardcoded cubes + collision + game loop. Everything else is bonus.

---

## File Structure After Day 7

```
src/
├── main.zig                    # native entry point
├── wasm_entry.zig              # WASM entry point (export fn init/update/onKey...)
├── root.zig                    # library root
├── math/
│   ├── scalar.zig              # Scalar type alias
│   ├── vec2.zig                # Vec2 (SIMD)
│   ├── vec3.zig                # Vec3 (SIMD, @Vector(4) with w=0)
│   ├── vec4.zig                # Vec4 (SIMD)
│   ├── mat.zig                 # Mat4
│   └── quat.zig                # Quaternion
├── memory/
│   ├── arena.zig               # Arena allocator
│   └── pool.zig                # Pool allocator
├── platform/
│   ├── platform.zig            # comptime target switch (web vs native)
│   ├── web.zig                 # WASM ↔ JS bridge (extern + export)
│   ├── native.zig              # macOS/Linux/Windows (optional)
│   └── input.zig               # Input state tracking
├── renderer/
│   ├── webgl.zig               # WebGL2 backend via JS bridge
│   ├── mesh.zig                # Mesh data + procedural geometry
│   ├── texture.zig             # Texture management
│   └── camera.zig              # Camera + projection
├── ecs/
│   ├── world.zig               # Entity storage + components
│   └── systems.zig             # Movement, render systems
├── physics/
│   ├── collision.zig           # AABB, sphere overlap
│   ├── rigidbody.zig           # Rigid body + integration
│   └── physics_system.zig      # Broad/narrow phase + response
├── audio/
│   └── mixer.zig               # Audio mixing (Web Audio via JS bridge)
├── assets/
│   ├── image.zig               # BMP loader / procedural textures
│   └── obj.zig                 # OBJ mesh loader
└── game/
    └── demo.zig                # Demo game logic
web/
├── index.html                  # HTML host page with <canvas>
└── engine.js                   # JS glue: WASM loader, WebGL, events, RAF loop
```
