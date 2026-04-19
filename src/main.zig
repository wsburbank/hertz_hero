const std = @import("std");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zopengl = @import("zopengl");

pub fn main() !void {
    _ = zopengl;

    try zglfw.init();
    defer zglfw.terminate();

    const window = try zglfw.Window.create(1280, 720, "Hertz Hero", null);
    defer window.destroy();
    zglfw.makeContextCurrent(window);

    zgui.init(std.heap.page_allocator);
    defer zgui.deinit();

    while (!window.shouldClose()) {
        zglfw.pollEvents();

        zgui.backend.newFrame(1280, 720);

        zgui.begin("Hertz Hero Dashboard", .{});
        zgui.text("Ready to analyze frequencies...", .{});
        if (zgui.button("Load MIDI", .{})) {}
        zgui.end();
    }
}
