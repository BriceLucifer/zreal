const std = @import("std");
const Io = std.Io;
const zreal = @import("zreal");
const Vec2 = zreal.Vec2;
const Vec3 = zreal.Vec3;

const width = 512;
const height = 512;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const file = try Io.Dir.createFile(.cwd(), io, "output.ppm", .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var file_writer = Io.File.Writer.init(file, io, &buf);
    const writer = &file_writer.interface;

    // PPM header: P3 = ASCII format
    try writer.print("P3\n{} {}\n255\n", .{ width, height });

    for (0..height) |py| {
        for (0..width) |px| {
            const x: f32 = @floatFromInt(px);
            const y: f32 = @floatFromInt(py);

            // Normalize pixel coords to 0..1
            const uv = Vec2.init(.{ x / width, y / height });

            // Distance from center
            const center = Vec2.init(.{ 0.5, 0.5 });
            const diff = uv.sub(center);
            const dist = diff.length();

            // Radial gradient: orange center → dark blue edge
            const t = std.math.clamp(dist * 2.0, 0.0, 1.0);
            const inner = Vec3.init(1.0, 0.6, 0.2);
            const outer = Vec3.init(0.1, 0.1, 0.4);
            const color = inner.lerp(outer, t);

            // Float 0..1 → u8 0..255
            const r: u8 = @intFromFloat(std.math.clamp(color.x() * 255.0, 0.0, 255.0));
            const g: u8 = @intFromFloat(std.math.clamp(color.y() * 255.0, 0.0, 255.0));
            const b: u8 = @intFromFloat(std.math.clamp(color.z() * 255.0, 0.0, 255.0));

            try writer.print("{} {} {} ", .{ r, g, b });
        }
        try writer.print("\n", .{});
    }

    try writer.flush();
    std.debug.print("wrote output.ppm ({}x{})\n", .{ width, height });
}
