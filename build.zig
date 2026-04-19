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
