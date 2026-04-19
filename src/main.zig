const std = @import("std");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zopengl = @import("zopengl");

const window_width = 1280;
const window_height = 720;

pub fn main() !void {
    // Reserved for upcoming OpenGL setup in the render path.
    _ = zopengl;

    try zglfw.init();
    defer zglfw.terminate();

    const window = try zglfw.Window.create(window_width, window_height, "Hertz Hero", null);
    defer window.destroy();
    zglfw.makeContextCurrent(window);

    zgui.init(std.heap.page_allocator);
    defer zgui.deinit();

    while (!window.shouldClose()) {
        zglfw.pollEvents();

        zgui.backend.newFrame(window_width, window_height);

        zgui.begin("Hertz Hero Dashboard", .{});
        zgui.text("Ready to analyze frequencies...", .{});
        if (zgui.button("Load MIDI", .{})) {}
        zgui.end();
    }
}
