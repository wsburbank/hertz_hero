const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "hertz_hero",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Clay UI layout engine (via zclay Zig bindings)
    const zclay = b.dependency("zclay", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("clay", zclay.module("zclay"));

    // zglfw for window management
    const zglfw = b.dependency("zglfw", .{
        .target = target,
    });
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.root_module.linkLibrary(zglfw.artifact("glfw"));

    // zopengl for OpenGL bindings
    const zopengl = b.dependency("zopengl", .{});
    exe.root_module.addImport("zopengl", zopengl.module("root"));
    exe.root_module.linkLibrary(zopengl.artifact("zopengl"));

    // miniaudio for audio playback
    exe.addCSourceFile(.{
        .file = b.path("libs/miniaudio/miniaudio.c"),
        .flags = &.{},
    });
    exe.addIncludePath(b.path("libs/miniaudio"));
    exe.root_module.addIncludePath(b.path("libs/miniaudio"));

    // stb_truetype for font rasterization and text measurement
    exe.addCSourceFile(.{
        .file = b.path("libs/stb/stb_truetype.c"),
        .flags = &.{},
    });
    exe.addIncludePath(b.path("libs/stb"));
    exe.root_module.addIncludePath(b.path("libs/stb"));

    // FluidSynth for SoundFont synthesis
    exe.addIncludePath(b.path("libs/fluidsynth"));
    exe.root_module.addIncludePath(b.path("libs/fluidsynth"));
    exe.addLibraryPath(b.path("libs/fluidsynth/lib"));
    exe.linkSystemLibrary("libfluidsynth-3");

    // Win32 common dialogs (file open/save)
    exe.linkSystemLibrary("comdlg32");

    exe.linkLibC();
    b.installArtifact(exe);

    // Copy FluidSynth DLLs to output directory (cpp11 variant — only 2 DLLs needed)
    const fs_dlls = [_][]const u8{
        "libfluidsynth-3.dll",
        "sndfile.dll",
    };
    for (fs_dlls) |dll| {
        const install_dll = b.addInstallBinFile(b.path(b.fmt("libs/fluidsynth/bin/{s}", .{dll})), dll);
        b.getInstallStep().dependOn(&install_dll.step);
    }

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const exe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
