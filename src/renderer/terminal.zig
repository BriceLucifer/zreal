const std = @import("std");
const Framebuffer = @import("framebuffer.zig").Framebuffer;

/// Renders a framebuffer to the terminal using ANSI 24-bit color and '▀' half-block.
/// Writes into a pre-allocated buffer, returns the slice that was written.
pub fn renderToBuffer(fb: *const Framebuffer, buf: []u8) usize {
    var pos: usize = 0;

    // Move cursor to top-left
    const home = "\x1b[H";
    @memcpy(buf[pos..][0..home.len], home);
    pos += home.len;

    const w = fb.width;
    const h = fb.height;

    var y: u32 = 0;
    while (y + 1 < h) : (y += 2) {
        const row_top = @as(usize, y) * @as(usize, w);
        const row_bot = @as(usize, y + 1) * @as(usize, w);

        var x: u32 = 0;
        while (x < w) : (x += 1) {
            const top = fb.pixels[row_top + x];
            const bot = fb.pixels[row_bot + x];

            // Write ANSI escape: \x1b[38;2;R;G;Bm\x1b[48;2;R;G;Bm▀
            pos += writeAnsiPixel(buf[pos..], top.r, top.g, top.b, bot.r, bot.g, bot.b);
        }
        // Reset + newline
        const reset_nl = "\x1b[0m\n";
        @memcpy(buf[pos..][0..reset_nl.len], reset_nl);
        pos += reset_nl.len;
    }

    return pos;
}

fn writeAnsiPixel(buf: []u8, fr: u8, fg: u8, fb_: u8, br: u8, bg: u8, bb: u8) usize {
    // \x1b[38;2;RRR;GGG;BBBm\x1b[48;2;RRR;GGG;BBBm▀
    // Max length: 2+5+1+3+1+3+1+3+1 + 2+5+1+3+1+3+1+3+1 + 3 = ~40 bytes
    var pos: usize = 0;

    // Foreground
    buf[pos] = 0x1b;
    pos += 1;
    buf[pos] = '[';
    pos += 1;
    buf[pos] = '3';
    pos += 1;
    buf[pos] = '8';
    pos += 1;
    buf[pos] = ';';
    pos += 1;
    buf[pos] = '2';
    pos += 1;
    buf[pos] = ';';
    pos += 1;
    pos += writeU8(buf[pos..], fr);
    buf[pos] = ';';
    pos += 1;
    pos += writeU8(buf[pos..], fg);
    buf[pos] = ';';
    pos += 1;
    pos += writeU8(buf[pos..], fb_);
    buf[pos] = 'm';
    pos += 1;

    // Background
    buf[pos] = 0x1b;
    pos += 1;
    buf[pos] = '[';
    pos += 1;
    buf[pos] = '4';
    pos += 1;
    buf[pos] = '8';
    pos += 1;
    buf[pos] = ';';
    pos += 1;
    buf[pos] = '2';
    pos += 1;
    buf[pos] = ';';
    pos += 1;
    pos += writeU8(buf[pos..], br);
    buf[pos] = ';';
    pos += 1;
    pos += writeU8(buf[pos..], bg);
    buf[pos] = ';';
    pos += 1;
    pos += writeU8(buf[pos..], bb);
    buf[pos] = 'm';
    pos += 1;

    // ▀ (U+2580) = 0xE2 0x96 0x80
    buf[pos] = 0xE2;
    pos += 1;
    buf[pos] = 0x96;
    pos += 1;
    buf[pos] = 0x80;
    pos += 1;

    return pos;
}

fn writeU8(buf: []u8, val: u8) usize {
    if (val >= 100) {
        buf[0] = '0' + val / 100;
        buf[1] = '0' + (val / 10) % 10;
        buf[2] = '0' + val % 10;
        return 3;
    } else if (val >= 10) {
        buf[0] = '0' + val / 10;
        buf[1] = '0' + val % 10;
        return 2;
    } else {
        buf[0] = '0' + val;
        return 1;
    }
}

pub fn writeStr(fd: std.posix.fd_t, data: []const u8) !void {
    var written: usize = 0;
    while (written < data.len) {
        const remaining = data[written..];
        const result = std.c.write(fd, remaining.ptr, remaining.len);
        if (result < 0) {
            const err = std.posix.errno(result);
            if (err == .AGAIN or err == .INTR) continue;
            return error.WriteFailed;
        }
        written += @intCast(result);
    }
}
