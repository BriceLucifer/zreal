const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Shared library module ─────────────────────────────────────────
    const mod = b.addModule("zreal", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // ── Native executable ─────────────────────────────────────────────
    const exe = b.addExecutable(.{
        .name = "zreal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zreal", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // ── WASM build ────────────────────────────────────────────────────
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const wasm = b.addExecutable(.{
        .name = "zreal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm_entry.zig"),
            .target = wasm_target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "zreal", .module = b.addModule("zreal-wasm", .{
                    .root_source_file = b.path("src/root.zig"),
                    .target = wasm_target,
                }) },
            },
        }),
    });

    wasm.entry = .disabled; // library, not executable

    // Explicitly export all API functions so wasm-ld doesn't strip them
    wasm.root_module.export_symbol_names = &.{
        "init", "frame", "restart",
        "setInput", "setFire", "setAspect",
        "getScore", "getCombo", "getWave", "getHP",
        "getGameState", "getShield", "getTriple", "getTime", "getShake",
        "getRenderCount", "getRenderKind", "getRenderColor", "getRenderGlow",
        "getVpPtr", "getMvpPtr", "getModelPtr",
        "getParticleCount", "getParticleDataPtr",
    };

    const wasm_step = b.step("wasm", "Build WASM module");
    const install_wasm = b.addInstallArtifact(wasm, .{
        .dest_dir = .{ .override = .{ .custom = "../web" } },
    });
    wasm_step.dependOn(&install_wasm.step);

    // ── Tests ─────────────────────────────────────────────────────────
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
