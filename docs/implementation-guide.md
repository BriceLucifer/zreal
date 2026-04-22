# zreal CPU Software Renderer — Implementation Guide

从零实现一个 SIMD 加速的 CPU 3D 软件渲染引擎，跑在终端里，可以玩一个简单的 3D 游戏。

---

## Architecture Overview

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│  Game Loop  │────►│  Rasterizer  │────►│ Framebuffer │────►│  Terminal    │
│  (main.zig) │     │  (SIMD math) │     │  (pixels+Z) │     │  (ANSI out)  │
└──────┬──────┘     └──────────────┘     └─────────────┘     └──────────────┘
       │
  ┌────┴─────┐
  │  Camera  │   ←── lookAt + perspective (Mat4)
  │  Physics │   ←── AABB collision (Vec4 ops)
  │  Input   │   ←── raw terminal (posix termios)
  └──────────┘
```

---

## Step 1: Math Library (SIMD)

**关键洞察**: Zig 的 `@Vector(4, f32)` 直接映射到 CPU SIMD 指令（SSE/NEON），不需要任何 intrinsics wrapper。

### 1.1 Scalar + Vec2/Vec3/Vec4

文件: `src/math/scalar.zig`, `src/math/vec2.zig`, `src/math/vec3.zig`, `src/math/vec4.zig`

```zig
// 核心: 所有向量都用 @Vector 存储
pub const Vec3 = struct {
    data: @Vector(4, f32),  // 用 4-wide SIMD，w=0，填满 128-bit 寄存器

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return @reduce(.Add, self.data * other.data);  // 一条 SIMD 指令
    }
};
```

**要实现的操作**:
- `init`, `x()/y()/z()/w()` — 构造和访问
- `add`, `sub` — SIMD 向量加减 (`self.data + other.data`)
- `scale` — 标量乘 (用 `@splat` 广播标量到 SIMD 寄存器)
- `dot` — 点积 (`@reduce(.Add, a * b)`)
- `length` — `@sqrt(dot(self, self))`
- `normalize` — `self.scale(1.0 / self.length())`
- `cross` (Vec3) — 用 `@shuffle` 实现，避免标量运算
- `lerp` — 线性插值

**Vec3 cross 的 SIMD trick**:
```zig
pub fn cross(self: Vec3, other: Vec3) Vec3 {
    // a × b = a_yzx * b_zxy - a_zxy * b_yzx
    const a_yzx = @shuffle(f32, self.data, undefined, [4]i32{ 1, 2, 0, 3 });
    const a_zxy = @shuffle(f32, self.data, undefined, [4]i32{ 2, 0, 1, 3 });
    const b_yzx = @shuffle(f32, other.data, undefined, [4]i32{ 1, 2, 0, 3 });
    const b_zxy = @shuffle(f32, other.data, undefined, [4]i32{ 2, 0, 1, 3 });
    const result = a_yzx * b_zxy - a_zxy * b_yzx;
    return .{ .data = .{ result[0], result[1], result[2], 0 } };
}
```

**测试**: dot、cross、normalize、length 的数值正确性。

### 1.2 Mat4 (4x4 矩阵)

文件: `src/math/mat.zig`

**存储**: Column-major，4 个 `@Vector(4, f32)` 列。

```zig
pub const Mat4 = struct {
    cols: [4]@Vector(4, f32),
};
```

**矩阵×向量 (核心性能热点)**:
```zig
fn mulCol(self: Mat4, col: @Vector(4, f32)) @Vector(4, f32) {
    const V = @Vector(4, f32);
    var result = self.cols[0] * @as(V, @splat(col[0]));
    result = @mulAdd(V, self.cols[1], @as(V, @splat(col[1])), result);  // FMA!
    result = @mulAdd(V, self.cols[2], @as(V, @splat(col[2])), result);
    result = @mulAdd(V, self.cols[3], @as(V, @splat(col[3])), result);
    return result;
}
```

`@mulAdd` 编译成 FMA (Fused Multiply-Add) 指令，一个时钟周期完成乘法+加法。

**要实现的函数**:
- `identity` — 单位矩阵 (comptime const)
- `translation(x, y, z)` — 平移矩阵
- `scaling(x, y, z)` — 缩放矩阵
- `rotationX/Y/Z(angle)` — 绕轴旋转
- `mul(Mat4, Mat4)` — 矩阵乘法（4次 mulCol）
- `mulVec4(Vec4)` — 矩阵×向量
- `transpose()` — 转置
- `lookAt(eye, target, up)` — 视图矩阵
- `perspective(fov, aspect, near, far)` — 透视投影

**lookAt 算法**:
```
forward = normalize(eye - target)
right   = normalize(cross(world_up, forward))
up      = cross(forward, right)

     ┌ right.x   up.x   fwd.x   0 ┐
V =  │ right.y   up.y   fwd.y   0 │
     │ right.z   up.z   fwd.z   0 │
     └ -dot(r,e) -dot(u,e) -dot(f,e) 1 ┘
```

**perspective 算法** (OpenGL convention, depth [-1,1]):
```
f = 1 / tan(fov/2)
range_inv = 1 / (near - far)

     ┌ f/aspect  0    0                    0 ┐
P =  │ 0         f    0                    0 │
     │ 0         0    (far+near)*range_inv -1 │
     └ 0         0    2*far*near*range_inv  0 ┘
```

### 1.3 Quaternion (可选但推荐)

文件: `src/math/quat.zig`

存储: `@Vector(4, f32)` — x, y, z, w

**要实现**: `fromAxisAngle`, `mul`, `conjugate`, `normalize`, `toMat4`, `slerp`

---

## Step 2: Framebuffer + Software Rasterizer

文件: `src/renderer/framebuffer.zig`

这是引擎的心脏。一个 CPU 上的 "GPU"。

### 2.1 数据结构

```zig
pub const Color = struct { r: u8, g: u8, b: u8 };

pub const Vertex = struct {
    pos: Vec4,     // 物体空间坐标 (w=1)
    color: Vec3,   // 顶点颜色 (0..1)
    normal: Vec3,  // 顶点法线
};

pub const Framebuffer = struct {
    width: u32,
    height: u32,
    pixels: []Color,   // 颜色缓冲
    depth: []f32,      // 深度缓冲 (z-buffer)
};
```

### 2.2 核心: drawTriangle

**渲染管线 (每个三角形)**:

```
1. MVP Transform    — 顶点 × MVP 矩阵 → 裁剪空间
2. Perspective Divide — ÷ w → NDC [-1,1]
3. Viewport Transform — NDC → 屏幕像素坐标
4. Backface Cull     — edge function < 0 → 跳过
5. Bounding Box      — 只扫描三角形覆盖的像素
6. Barycentric Test  — 每个像素: 在三角形内?
7. Depth Test        — z < depth_buffer? 才写入
8. Shading           — 插值颜色 + 光照
```

**Edge Function (三角形面积判断)**:
```zig
fn edgeFn(ax, ay, bx, by, cx, cy: f32) f32 {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}
```

- `edgeFn(v0, v1, v2) > 0` → 正面 (counter-clockwise)
- 对每个像素 P: `w0 = edgeFn(v1, v2, P)`, `w1 = edgeFn(v2, v0, P)`, `w2 = 1 - w0 - w1`
- 三个权重都 >= 0 → 像素在三角形内

**光照 (简单 Lambertian)**:
```zig
const face_normal = normalize(cross(v1-v0, v2-v0));
const ndotl = max(0, dot(face_normal, light_dir));
const lit_color = color * (ambient + (1-ambient) * ndotl);
```

### 2.3 深度测试

```zig
pub fn setPixel(self: *Framebuffer, px: u32, py: u32, z: f32, color: Color) void {
    const idx = py * self.width + px;
    if (z < self.depth[idx]) {  // 更近的物体覆盖更远的
        self.depth[idx] = z;
        self.pixels[idx] = color;
    }
}
```

每帧开始 `clear()` 将 depth buffer 重置为 1.0（最远）。

---

## Step 3: Camera

文件: `src/renderer/camera.zig`

```zig
pub const Camera = struct {
    pos: Vec4,
    yaw: f32,     // 水平旋转 (弧度)
    pitch: f32,   // 垂直旋转 (弧度, 夹紧防止万向锁)
    fov: f32,
    aspect: f32,
    near: f32,
    far: f32,
};
```

**forward 方向**: 从 yaw/pitch 计算
```zig
pub fn forward(self: Camera) Vec4 {
    return Vec4.init(
        sin(yaw) * cos(pitch),
        sin(pitch),
        -cos(yaw) * cos(pitch),  // 注意负号: 相机默认看 -Z
        0,
    );
}
```

**viewProjection = projection × view**（注意乘法顺序！）

---

## Step 4: Mesh / Geometry

文件: `src/renderer/mesh.zig`

```zig
pub const Mesh = struct {
    vertices: []const Vertex,
    indices: []const [3]u32,  // 三角形索引
};
```

**Cube**: 6 个面 × 4 个顶点 = 24 个顶点（每个面有自己的法线）。12 个三角形。

用 `comptime` 在编译期生成顶点和索引数组 — 零运行时开销。

**Floor**: 2 个三角形组成一个大四边形。

---

## Step 5: Terminal Renderer

文件: `src/renderer/terminal.zig`

**核心技巧**: Unicode 半块字符 `▀` (U+2580) 将前景色和背景色分别映射到上下两行像素，有效分辨率翻倍。

```
前景色 = 上面那行像素的颜色
背景色 = 下面那行像素的颜色
字符 = ▀ (上半块)
```

**ANSI 24-bit 颜色**:
```
\x1b[38;2;R;G;Bm  — 设置前景色
\x1b[48;2;R;G;Bm  — 设置背景色
```

**性能关键**: 
1. 所有输出先写入一个大 buffer
2. 一次 `write()` 系统调用输出整帧
3. 用手写的数字→字符串转换，避免 `std.fmt` 的开销

---

## Step 6: Raw Terminal Input

**termios 设置**:
```zig
var raw = original_termios;
raw.lflag.ECHO = false;     // 不回显
raw.lflag.ICANON = false;   // 不等回车
raw.lflag.ISIG = false;     // 不处理 Ctrl-C
raw.cc[V.MIN] = 0;          // 非阻塞
raw.cc[V.TIME] = 0;
```

每帧 `read(stdin, &buf)` → 解析按键 → 更新输入状态。

记得 defer 恢复原始 termios！

---

## Step 7: Game Loop

```
while (running) {
    dt = clock() - last_time;
    last_time = clock();

    readInput();
    updateCamera(dt);
    updatePhysics(dt);

    renderFrame();           // 3D → framebuffer
    terminalRender();        // framebuffer → ANSI buffer → write()

    sleep(frame_time - elapsed);  // 帧率限制
}
```

**时间**: 用 `clock_gettime(MONOTONIC)` 获取纳秒级时间戳。
**帧率限制**: `nanosleep()` 补齐剩余时间。
**spiral-of-death 保护**: `dt = min(dt, 0.1)` 防止帧卡顿时物理爆炸。

---

## Step 8: Demo Game — "Bouncing Arena"

**游戏逻辑**:
- **Arena**: 地板 + 4 面墙 (用缩放的 cube 画)
- **Player**: 第一人称相机，WASD 移动，Q/E 转向
- **Cubes**: 每 2 秒生成一个，在 arena 内弹跳
- **Collision**: AABB 碰撞检测 (简单的距离判断)
- **Score**: 走到 cube 附近 → 得分 → cube 消失

---

## Build & Run

```bash
# Debug build (有边界检查，方便调试)
zig build run

# Release build (开启 SIMD 优化，性能好很多)
zig build run -Doptimize=ReleaseFast

# 运行测试
zig build test
```

---

## 文件结构

```
src/
├── main.zig                    # 入口: 游戏循环 + 游戏逻辑 + 渲染
├── root.zig                    # 库 root (公开 API)
├── math.zig                    # 数学模块重导出
├── math/
│   ├── scalar.zig              # f32 类型别名
│   ├── vec2.zig                # Vec2 (@Vector(2, f32))
│   ├── vec3.zig                # Vec3 (@Vector(4, f32), w=0)
│   ├── vec4.zig                # Vec4 (@Vector(4, f32))
│   ├── mat.zig                 # Mat4 (column-major, @mulAdd)
│   └── quat.zig                # Quaternion
├── renderer.zig                # 渲染模块重导出
└── renderer/
    ├── framebuffer.zig         # 帧缓冲 + 光栅化器 + 深度测试
    ├── camera.zig              # FPS 相机
    ├── mesh.zig                # 几何体生成 (cube, floor)
    └── terminal.zig            # ANSI 终端渲染
```

---

## 性能 Notes

1. **所有向量运算都是 SIMD** — `@Vector(4, f32)` 在 x86 上编译成 SSE 指令，ARM 上编译成 NEON
2. **Mat4 乘法用 FMA** — `@mulAdd` = 一条指令完成 multiply-add
3. **Cube 索引数组是 comptime** — 编译期计算，运行时零开销
4. **终端输出单次 write** — 整帧写入一个 buffer，一次系统调用输出，最小化 IO 开销
5. **手写数字转换** — 避免 `std.fmt` 的通用格式化开销
6. **用 ReleaseFast 编译** 会自动 inline + 展开循环 + 启用 SIMD 优化

---

## 可以扩展的方向

- [ ] 纹理映射 (UV 坐标 + 棋盘格纹理)
- [ ] 更多几何体 (球体、平面)
- [ ] OBJ 文件加载
- [ ] Phong 高光
- [ ] 视锥裁剪 (近平面 clipping)
- [ ] 多线程光栅化 (按 tile 分任务)
- [ ] WASM + WebGL 后端
