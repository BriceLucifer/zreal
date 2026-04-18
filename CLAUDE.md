# zreal — Zig Game Engine

## Project Vision

Build a game engine from scratch in pure Zig with **zero external libraries**. Every subsystem — math, rendering, physics, audio, input, asset loading — is implemented by hand.

## Why Zig

- **`@Vector` is hardware SIMD**: Zig's `@Vector(4, f32)` compiles directly to SSE/AVX/NEON instructions. No intrinsics wrappers, no library needed. This is the core motivation — real SIMD math at the language level.
- **`comptime`**: Generate lookup tables, unroll loops, specialize pipelines at compile time with zero runtime cost.
- **Manual memory control**: Arena allocators, pool allocators, and explicit allocation patterns — critical for a game engine's deterministic performance.
- **No hidden allocations, no GC, no exceptions**: You control every byte.
- **C ABI interop**: When you eventually need to talk to OS APIs (Vulkan, Metal, Win32, X11), Zig calls C directly — no bindings library needed.

## Constraints

- **No external Zig packages or C libraries** (except OS/platform APIs like Vulkan/Metal/X11/Win32/Cocoa which are system-provided)
- Everything is implemented in this repo
- Target: desktop platforms (macOS, Linux, Windows)

## Module Roadmap

The engine is built bottom-up in this order:

| Phase | Module | Description |
|-------|--------|-------------|
| 1 | `math` | Vec2/3/4, Mat3/4, Quaternion — all backed by `@Vector` SIMD |
| 2 | `memory` | Arena, pool, and scratch allocators |
| 3 | `platform` | Window creation, input events (OS-specific: Cocoa/X11/Win32) |
| 4 | `renderer` | Software rasterizer first, then GPU backend (Metal/Vulkan) |
| 5 | `ecs` | Entity-Component-System with SoA storage |
| 6 | `physics` | AABB/SAT collision, rigid body dynamics |
| 7 | `audio` | PCM mixing, spatial audio |
| 8 | `assets` | Image/mesh/audio loaders (BMP, OBJ, WAV — simple formats first) |
| 9 | `scene` | Scene graph, camera, transform hierarchy |
| 10 | `game` | Game loop, fixed timestep, frame timing |

## Build & Run

```bash
zig build          # build the engine
zig build run      # run the executable
zig build test     # run all tests
```

## Project Structure

```
src/
  main.zig         # entry point
  root.zig         # library root (public API)
  math/            # SIMD math library
  memory/          # custom allocators
  platform/        # OS window/input layer
  renderer/        # software rasterizer → GPU backend
  ecs/             # entity-component-system
  physics/         # collision & dynamics
  audio/           # audio mixer
  assets/          # file format loaders
  scene/           # scene graph & cameras
docs/
  game-engine-guide.md   # comprehensive engineering guide
```

## Documentation

- `docs/game-engine-guide.md` — Detailed engineering guide covering every subsystem (for zero game engine experience)
- `docs/one-week-plan.md` — Day-by-day build plan with checkboxes, deliverables, and cut-scope guidance
