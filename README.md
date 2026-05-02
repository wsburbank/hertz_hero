# Hertz Hero: Project Ignition Script

## Context for Copilot
Target Language: Zig (Version 0.13.0)
Graphics API: OpenGL 3.3 / GLFW
GUI: Dear ImGui (via zgui)
Audio: miniaudio (C-interop)
Goal: High-performance MIDI-to-Sheet Music Gamifier.

## Phase 1: Dependency Management
Create a `build.zig.zon` to handle zgui and zglfw dependencies.

### File: build.zig.zon
.{
    .name = "hertz-hero",
    .version = "0.1.0",
    .dependencies = .{
        .zgui = .{ .url = "https://github.com/zig-gamedev/zgui/archive/main.tar.gz" },
        .zglfw = .{ .url = "https://github.com/zig-gamedev/zglfw/archive/main.tar.gz" },
        .zopengl = .{ .url = "https://github.com/zig-gamedev/zopengl/archive/main.tar.gz" },
    },
    .paths = .{ "" },
}

## Phase 2: Build System
Configure `build.zig` to link C libraries and import the GUI modules.

### File: build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "hertz-hero",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Dependency Setup
    const zgui = b.dependency("zgui", .{
        .shared = false,
        .with_implot = true,
    });
    const zglfw = b.dependency("zglfw", .{});
    const zopengl = b.dependency("zopengl", .{});

    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.root_module.addImport("zopengl", zopengl.module("root"));

    exe.linkLibrary(zgui.artifact("imgui"));
    exe.linkLibrary(zglfw.artifact("glfw"));
    
    exe.linkLibC();
    b.installArtifact(exe);
}

## Phase 3: The Entry Point
A minimal Zig application that initializes a window and an ImGui context.

### File: src/main.zig
const std = @import("std");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zopengl = @import("zopengl");

pub fn main() !void {
    try zglfw.init();
    defer zglfw.terminate();

    const window = try zglfw.Window.create(1280, 720, "Hertz Hero", null);
    defer window.destroy();
    zglfw.makeContextCurrent(window);

    zgui.init(std.heap.page_allocator);
    defer zgui.deinit();

    // Main Loop
    while (!window.shouldClose()) {
        zglfw.pollEvents();
        
        zgui.backend.newFrame(1280, 720);
        
        zgui.begin("Hertz Hero Dashboard", .{});
        zgui.text("Ready to analyze frequencies...", .{});
        if (zgui.button("Load MIDI", .{})) {
            // Future MIDI Load Logic
        }
        zgui.end();

        // Rendering logic here
    }
}