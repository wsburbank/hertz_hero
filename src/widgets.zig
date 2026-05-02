const std = @import("std");
const clay = @import("clay");
const theme = @import("theme.zig");

// ============================================================================
// Input state — fed from main.zig each frame before beginLayout()
// ============================================================================

pub var mouse_x: f32 = 0;
pub var mouse_y: f32 = 0;
pub var mouse_down: bool = false;
pub var mouse_down_prev: bool = false;
pub var scroll_y_delta: f32 = 0;
pub var frame_time_ms: f64 = 0; // accumulated time for cursor blink

// Keyboard input ring buffer — filled by GLFW callbacks, consumed by widgets
const MAX_CHARS: usize = 16;
var char_buf: [MAX_CHARS]u8 = undefined;
var char_count: usize = 0;
var key_backspace: bool = false;
var key_enter: bool = false;
var key_escape: bool = false;

pub fn pushChar(codepoint: u32) void {
    if (codepoint < 128 and char_count < MAX_CHARS) {
        char_buf[char_count] = @intCast(codepoint);
        char_count += 1;
    }
}

pub fn pushKey(key: enum { backspace, enter, escape }) void {
    switch (key) {
        .backspace => key_backspace = true,
        .enter => key_enter = true,
        .escape => key_escape = true,
    }
}

/// Call once per frame before clay.beginLayout()
pub fn updateInput(mx: f32, my: f32, down: bool, scroll_dy: f32, delta_ms: f64) void {
    mouse_down_prev = mouse_down;
    mouse_x = mx;
    mouse_y = my;
    mouse_down = down;
    scroll_y_delta = scroll_dy;
    frame_time_ms += delta_ms;
}

/// Call once per frame after processing to clear keyboard state
pub fn clearFrameKeys() void {
    char_count = 0;
    key_backspace = false;
    key_enter = false;
    key_escape = false;
}

/// Call once per frame before clay.beginLayout() to reset per-frame widget flags.
/// any_slider_dragging will be set by sliders during layout; the value from the
/// previous frame is available between updateInput() and beginLayoutReset().
pub fn beginLayoutReset() void {
    any_slider_dragging = false;
}

pub fn mousePressed() bool {
    return mouse_down and !mouse_down_prev;
}

pub fn mouseReleased() bool {
    return !mouse_down and mouse_down_prev;
}

// ============================================================================
// Slider drag state — tracks which slider is being dragged
// ============================================================================

/// True when any slider is actively being dragged this frame.
/// Used by main.zig to suppress scroll-container drag scrolling.
pub var any_slider_dragging: bool = false;

pub const SliderState = struct {
    dragging: bool = false,
    // Cached bounding box from previous frame for drag computation
    prev_bb: clay.BoundingBox = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
};

// ============================================================================
// Combo box state
// ============================================================================

pub const ComboState = struct {
    open: bool = false,
};

// ============================================================================
// Button
// ============================================================================

pub const ButtonOpts = struct {
    w: f32 = 100,
    h: f32 = 40,
    font_size: u16 = 20,
};

/// Renders a button. Returns true if clicked this frame.
pub fn button(comptime label: []const u8, opts: ButtonOpts) bool {
    const id = clay.ElementId.localID(label);
    const is_hovered = clay.pointerOver(id);
    const bg = if (is_hovered and mouse_down)
        theme.button_active
    else if (is_hovered)
        theme.button_hover
    else
        theme.button_default;

    clay.UI()(.{
        .id = id,
        .layout = .{
            .sizing = .{ .w = .fixed(opts.w), .h = .fixed(opts.h) },
            .padding = .all(4),
            .child_alignment = .{ .x = .center, .y = .center },
        },
        .background_color = bg,
        .corner_radius = .all(theme.radius_button),
    })({
        clay.text(label, .{
            .font_size = opts.font_size,
            .color = theme.text_primary,
        });
    });

    return is_hovered and mouseReleased();
}

/// Dynamic-string button variant. Takes a runtime string and an index for unique ID.
pub fn buttonDyn(comptime id_base: []const u8, label: []const u8, index: u32, opts: ButtonOpts) bool {
    const id = clay.ElementId.localIDI(id_base, index);
    const is_hovered = clay.pointerOver(id);
    const bg = if (is_hovered and mouse_down)
        theme.button_active
    else if (is_hovered)
        theme.button_hover
    else
        theme.button_default;

    clay.UI()(.{
        .id = id,
        .layout = .{
            .sizing = .{ .w = .fixed(opts.w), .h = .fixed(opts.h) },
            .padding = .all(4),
            .child_alignment = .{ .x = .center, .y = .center },
        },
        .background_color = bg,
        .corner_radius = .all(theme.radius_button),
    })({
        clay.text(label, .{
            .font_size = opts.font_size,
            .color = theme.text_primary,
        });
    });

    return is_hovered and mouseReleased();
}

// ============================================================================
// Checkbox
// ============================================================================

pub const CheckboxOpts = struct {
    box_size: f32 = 24,
    font_size: u16 = 18,
};

/// Renders a checkbox with label. Returns true if toggled this frame.
pub fn checkbox(comptime label: []const u8, value: *bool, opts: CheckboxOpts) bool {
    const row_id = clay.ElementId.localID(label ++ "__cb_row");
    const box_id = clay.ElementId.localID(label ++ "__cb_box");

    clay.UI()(.{
        .id = row_id,
        .layout = .{
            .direction = .left_to_right,
            .child_gap = 8,
            .child_alignment = .{ .y = .center },
        },
    })({
        // Checkbox box
        const is_hovered = clay.pointerOver(box_id);
        const box_bg = if (value.*)
            theme.neon
        else if (is_hovered)
            theme.frame_bg_hover
        else
            theme.checkbox_bg;

        const check_fs: u16 = @intFromFloat(@max(8, @round(opts.box_size * 0.67)));

        clay.UI()(.{
            .id = box_id,
            .layout = .{
                .sizing = .{ .w = .fixed(opts.box_size), .h = .fixed(opts.box_size) },
                .child_alignment = .{ .x = .center, .y = .center },
            },
            .background_color = box_bg,
            .corner_radius = .all(4),
            .border = .{ .color = theme.border_default, .width = .outside(1) },
        })({
            if (value.*) {
                clay.text("X", .{
                    .font_size = check_fs,
                    .color = theme.text_primary,
                });
            }
        });

        // Label
        clay.text(label, .{
            .font_size = opts.font_size,
            .color = theme.text_primary,
        });
    });

    // Check for click on the whole row
    const clicked = clay.pointerOver(row_id) and mouseReleased();
    if (clicked) value.* = !value.*;
    return clicked;
}

// ============================================================================
// Slider Float
// ============================================================================

pub const SliderOpts = struct {
    width: f32 = 250,
    height: f32 = 24,
    font_size: u16 = 16,
    show_label: bool = true,
};

/// Renders a horizontal float slider. Returns true if value changed.
pub fn sliderFloat(
    comptime label: []const u8,
    value: *f32,
    min: f32,
    max: f32,
    state: *SliderState,
    opts: SliderOpts,
) bool {
    const track_id = clay.ElementId.localID(label ++ "__sl_track");
    const old_value = value.*;

    // Handle drag: use previous frame's bounding box
    if (state.dragging) {
        any_slider_dragging = true;
        if (!mouse_down) {
            state.dragging = false;
        } else {
            // Compute value from mouse position within track
            const bb = state.prev_bb;
            if (bb.width > 0) {
                const t = std.math.clamp((mouse_x - bb.x) / bb.width, 0, 1);
                value.* = min + t * (max - min);
            }
        }
    } else if (clay.pointerOver(track_id) and mousePressed()) {
        state.dragging = true;
        any_slider_dragging = true;
        const bb = state.prev_bb;
        if (bb.width > 0) {
            const t = std.math.clamp((mouse_x - bb.x) / bb.width, 0, 1);
            value.* = min + t * (max - min);
        }
    }

    // Update cached bounding box for next frame
    const elem_data = clay.getElementData(track_id);
    if (elem_data.found) {
        state.prev_bb = elem_data.bounding_box;
    }

    const frac = std.math.clamp((value.* - min) / (max - min), 0, 1);
    const fill_w: f32 = @max(2, frac * opts.width);

    // Layout
    clay.UI()(.{
        .id = clay.ElementId.localID(label ++ "__sl_row"),
        .layout = .{
            .direction = .left_to_right,
            .child_gap = 10,
            .child_alignment = .{ .y = .center },
        },
    })({
        // Label
        if (opts.show_label) {
            clay.text(label, .{
                .font_size = opts.font_size,
                .color = theme.text_primary,
            });
        }

        // Track background
        clay.UI()(.{
            .id = track_id,
            .layout = .{
                .sizing = .{
                    .w = .fixed(opts.width),
                    .h = .fixed(opts.height),
                },
            },
            .background_color = theme.slider_track,
            .corner_radius = .all(theme.radius_grab),
            .border = .{ .color = theme.border_default, .width = .outside(1) },
        })({
            // Fill
            clay.UI()(.{
                .layout = .{
                    .sizing = .{ .w = .fixed(fill_w), .h = .grow },
                },
                .background_color = if (state.dragging) theme.slider_grab_active else theme.slider_grab,
                .corner_radius = .all(theme.radius_grab),
            })({});
        });

        // Value display
        var buf: [16]u8 = undefined;
        const val_str = std.fmt.bufPrint(&buf, "{d:.1}", .{value.*}) catch "?";
        clay.text(val_str, .{
            .font_size = opts.font_size,
            .color = theme.neon,
        });
    });

    return value.* != old_value;
}

/// Indexed slider variant for use inside loops (e.g. per-track volume).
/// The index makes each slider's Clay element IDs unique.
pub fn sliderFloatI(
    comptime id_base: []const u8,
    label_text: []const u8,
    index: u32,
    value: *f32,
    min: f32,
    max: f32,
    state: *SliderState,
    opts: SliderOpts,
) bool {
    const track_id = clay.ElementId.localIDI(id_base ++ "__sl_track", index);
    const old_value = value.*;

    // Handle drag: use previous frame's bounding box
    if (state.dragging) {
        any_slider_dragging = true;
        if (!mouse_down) {
            state.dragging = false;
        } else {
            const bb = state.prev_bb;
            if (bb.width > 0) {
                const t = std.math.clamp((mouse_x - bb.x) / bb.width, 0, 1);
                value.* = min + t * (max - min);
            }
        }
    } else if (clay.pointerOver(track_id) and mousePressed()) {
        state.dragging = true;
        any_slider_dragging = true;
        const bb = state.prev_bb;
        if (bb.width > 0) {
            const t = std.math.clamp((mouse_x - bb.x) / bb.width, 0, 1);
            value.* = min + t * (max - min);
        }
    }

    // Update cached bounding box for next frame
    const elem_data = clay.getElementData(track_id);
    if (elem_data.found) {
        state.prev_bb = elem_data.bounding_box;
    }

    const frac = std.math.clamp((value.* - min) / (max - min), 0, 1);
    const fill_w: f32 = @max(2, frac * opts.width);

    // Layout
    clay.UI()(.{
        .id = clay.ElementId.localIDI(id_base ++ "__sl_row", index),
        .layout = .{
            .direction = .left_to_right,
            .child_gap = 10,
            .child_alignment = .{ .y = .center },
        },
    })({
        // Label
        if (opts.show_label) {
            clay.text(label_text, .{
                .font_size = opts.font_size,
                .color = theme.text_primary,
            });
        }

        // Track background
        clay.UI()(.{
            .id = track_id,
            .layout = .{
                .sizing = .{
                    .w = .fixed(opts.width),
                    .h = .fixed(opts.height),
                },
            },
            .background_color = theme.slider_track,
            .corner_radius = .all(theme.radius_grab),
            .border = .{ .color = theme.border_default, .width = .outside(1) },
        })({
            // Fill
            clay.UI()(.{
                .id = clay.ElementId.localIDI(id_base ++ "__sl_fill", index),
                .layout = .{
                    .sizing = .{ .w = .fixed(fill_w), .h = .grow },
                },
                .background_color = if (state.dragging) theme.slider_grab_active else theme.slider_grab,
                .corner_radius = .all(theme.radius_grab),
            })({});
        });

        // Value display
        var buf: [16]u8 = undefined;
        const val_str = std.fmt.bufPrint(&buf, "{d:.1}", .{value.*}) catch "?";
        clay.text(val_str, .{
            .font_size = opts.font_size,
            .color = theme.neon,
        });
    });

    return value.* != old_value;
}

// ============================================================================
// Combo Box / Dropdown
// ============================================================================

pub const ComboOpts = struct {
    width: f32 = 250,
    max_visible_items: usize = 10,
    item_height: f32 = 28,
    font_size: u16 = 16,
};

/// Renders a combo box / dropdown. Returns true if selection changed.
pub fn combo(
    comptime label: []const u8,
    current_item: *i32,
    items: []const []const u8,
    state: *ComboState,
    opts: ComboOpts,
) bool {
    const btn_id = clay.ElementId.localID(label ++ "__co_btn");
    const old_item = current_item.*;

    // Close dropdown if clicked outside
    if (state.open and mouseReleased() and !clay.pointerOver(clay.ElementId.localID(label ++ "__co_drop"))) {
        if (!clay.pointerOver(btn_id)) {
            state.open = false;
        }
    }

    // Main button
    const is_hovered = clay.pointerOver(btn_id);
    clay.UI()(.{
        .id = btn_id,
        .layout = .{
            .sizing = .{
                .w = .fixed(opts.width),
                .h = .fixed(32),
            },
            .padding = .{ .left = 8, .right = 8, .top = 4, .bottom = 4 },
            .direction = .left_to_right,
            .child_alignment = .{ .y = .center },
        },
        .background_color = if (is_hovered) theme.frame_bg_hover else theme.frame_bg,
        .corner_radius = .all(4),
        .border = .{ .color = if (state.open) theme.neon else theme.border_default, .width = .outside(1) },
    })({
        const idx: usize = @intCast(std.math.clamp(current_item.*, 0, @as(i32, @intCast(items.len)) - 1));
        clay.text(items[idx], .{
            .font_size = opts.font_size,
            .color = theme.text_primary,
        });
    });

    // Toggle on click
    if (clay.pointerOver(btn_id) and mouseReleased()) {
        state.open = !state.open;
    }

    // Floating dropdown
    if (state.open) {
        const visible: usize = @min(opts.max_visible_items, items.len);
        const drop_h: f32 = @as(f32, @floatFromInt(visible)) * opts.item_height + 4.0;

        clay.UI()(.{
            .id = clay.ElementId.localID(label ++ "__co_drop"),
            .floating = .{
                .attach_to = .to_parent,
                .attach_points = .{
                    .element = .left_top,
                    .parent = .left_bottom,
                },
                .z_index = 100,
            },
            .layout = .{
                .sizing = .{
                    .w = .fixed(opts.width),
                    .h = .fixed(drop_h),
                },
                .padding = .all(2),
                .direction = .top_to_bottom,
            },
            .background_color = theme.bg_popup,
            .corner_radius = .all(4),
            .border = .{ .color = theme.border_default, .width = .outside(1) },
            .clip = .{ .vertical = true },
        })({
            for (items, 0..) |item, i| {
                const item_id = clay.ElementId.localIDI(label ++ "__co_item", @intCast(i));
                const item_hovered = clay.pointerOver(item_id);
                const item_selected = (@as(i32, @intCast(i)) == current_item.*);

                clay.UI()(.{
                    .id = item_id,
                    .layout = .{
                        .sizing = .{ .w = .grow, .h = .fixed(opts.item_height) },
                        .padding = .{ .left = 8, .top = 4, .bottom = 4, .right = 4 },
                        .child_alignment = .{ .y = .center },
                    },
                    .background_color = if (item_selected)
                        theme.neon_subtle
                    else if (item_hovered)
                        theme.header_hover
                    else
                        theme.transparent,
                })({
                    clay.text(item, .{
                        .font_size = opts.font_size,
                        .color = if (item_selected) theme.neon_bright else theme.text_primary,
                    });
                });

                if (item_hovered and mouseReleased()) {
                    current_item.* = @intCast(i);
                    state.open = false;
                }
            }
        });
    }

    return current_item.* != old_item;
}

// ============================================================================
// Tree Node (Collapsible Section)
// ============================================================================

/// Renders a collapsible tree node header. Returns true if currently open.
/// Caller should conditionally render children when this returns true.
pub fn treeNode(comptime label: []const u8, open: *bool) bool {
    const header_id = clay.ElementId.localID(label ++ "__tn_hdr");
    const is_hovered = clay.pointerOver(header_id);

    clay.UI()(.{
        .id = header_id,
        .layout = .{
            .sizing = .{ .w = .grow, .h = .fixed(30) },
            .direction = .left_to_right,
            .child_gap = 6,
            .child_alignment = .{ .y = .center },
            .padding = .{ .left = 4, .right = 4, .top = 2, .bottom = 2 },
        },
        .background_color = if (is_hovered) theme.header_hover else theme.header_default,
        .corner_radius = .all(4),
    })({
        // Arrow indicator
        const arrow: []const u8 = if (open.*) "v" else ">";
        clay.text(arrow, .{
            .font_size = 16,
            .color = theme.neon,
        });

        // Label
        clay.text(label, .{
            .font_size = 18,
            .color = theme.text_primary,
        });
    });

    if (is_hovered and mouseReleased()) {
        open.* = !open.*;
    }

    return open.*;
}

// ============================================================================
// Text helpers
// ============================================================================

/// Runtime-string tree node variant. Uses an index for unique Clay ID.
pub fn treeNodeDyn(label: []const u8, index: u32, open: *bool) bool {
    const header_id = clay.ElementId.localIDI("__tn_hdr", index);
    const is_hovered = clay.pointerOver(header_id);

    clay.UI()(.{
        .id = header_id,
        .layout = .{
            .sizing = .{ .w = .grow, .h = .fixed(30) },
            .direction = .left_to_right,
            .child_gap = 6,
            .child_alignment = .{ .y = .center },
            .padding = .{ .left = 4, .right = 4, .top = 2, .bottom = 2 },
        },
        .background_color = if (is_hovered) theme.header_hover else theme.header_default,
        .corner_radius = .all(4),
    })({
        const arrow: []const u8 = if (open.*) "v" else ">";
        clay.text(arrow, .{ .font_size = 16, .color = theme.neon });
        clay.text(label, .{ .font_size = 18, .color = theme.text_primary });
    });

    if (is_hovered and mouseReleased()) {
        open.* = !open.*;
    }

    return open.*;
}

/// Simple labeled text display
pub fn labeledText(comptime label: []const u8, value: []const u8) void {
    clay.UI()(.{
        .layout = .{
            .direction = .left_to_right,
            .child_gap = 8,
            .child_alignment = .{ .y = .center },
        },
    })({
        clay.text(label, .{
            .font_size = 16,
            .color = theme.text_disabled,
        });
        clay.text(value, .{
            .font_size = 16,
            .color = theme.text_primary,
        });
    });
}

/// Separator line
pub fn separator() void {
    clay.UI()(.{
        .layout = .{
            .sizing = .{ .w = .grow, .h = .fixed(1) },
        },
        .background_color = theme.separator_default,
    })({});
}

// ============================================================================
// Number Input (up/down arrows + value display)
// ============================================================================

pub const NumberInputOpts = struct {
    btn_size: f32 = 28,
    font_size: u16 = 16,
    display_width: f32 = 60,
    step: f32 = 0.05,
    min: f32 = 0.5,
    max: f32 = 3.0,
    /// If true, display and accept value as percentage (e.g. 1.0 -> "100%")
    as_percent: bool = false,
};

pub const NumberInputState = struct {
    editing: bool = false,
    selected_all: bool = false, // true when text is fully selected (first key replaces all)
    buf: [12]u8 = undefined,
    len: usize = 0,
    blink_start: f64 = 0,
    // Persistent display buffer so clay.text() has a stable pointer
    display_buf: [16]u8 = undefined,
    display_len: usize = 0,

    fn appendChar(self: *NumberInputState, c: u8) void {
        if (self.selected_all) {
            // Replace entire content with the new character
            self.buf[0] = c;
            self.len = 1;
            self.selected_all = false;
            return;
        }
        if (self.len < self.buf.len - 1) {
            self.buf[self.len] = c;
            self.len += 1;
        }
    }

    fn deleteChar(self: *NumberInputState) void {
        if (self.selected_all) {
            // Delete all selected text
            self.len = 0;
            self.selected_all = false;
            return;
        }
        if (self.len > 0) self.len -= 1;
    }

    fn editSlice(self: *const NumberInputState) []const u8 {
        return self.buf[0..self.len];
    }

    fn startEditing(self: *NumberInputState, value: f32, as_percent: bool) void {
        self.editing = true;
        self.selected_all = true;
        self.blink_start = frame_time_ms;
        const display_val = if (as_percent) value * 100.0 else value;
        const result = std.fmt.bufPrint(&self.buf, "{d:.0}", .{display_val}) catch {
            self.len = 0;
            return;
        };
        self.len = result.len;
    }

    fn commit(self: *NumberInputState, value: *f32, opts: NumberInputOpts) void {
        if (self.len > 0) {
            if (std.fmt.parseFloat(f32, self.editSlice())) |parsed| {
                const raw = if (opts.as_percent) parsed / 100.0 else parsed;
                value.* = std.math.clamp(raw, opts.min, opts.max);
            } else |_| {}
        }
        self.editing = false;
        self.selected_all = false;
    }

    fn cancel(self: *NumberInputState) void {
        self.editing = false;
        self.selected_all = false;
    }

    /// Format the current display string into the persistent buffer and return a stable slice.
    fn formatDisplay(self: *NumberInputState, value: f32, opts: NumberInputOpts) []const u8 {
        if (self.editing) {
            const src = self.editSlice();
            // Blinking cursor: 500ms on, 500ms off
            const show_cursor = !self.selected_all and (@as(u64, @intFromFloat(frame_time_ms - self.blink_start)) / 500 % 2 == 0);
            if (show_cursor) {
                @memcpy(self.display_buf[0..src.len], src);
                self.display_buf[src.len] = '|';
                self.display_len = src.len + 1;
            } else {
                @memcpy(self.display_buf[0..src.len], src);
                self.display_len = src.len;
            }
        } else if (opts.as_percent) {
            const result = std.fmt.bufPrint(&self.display_buf, "{d:.0}%", .{value * 100.0}) catch {
                self.display_buf[0] = '?';
                self.display_len = 1;
                return self.display_buf[0..1];
            };
            self.display_len = result.len;
        } else {
            const result = std.fmt.bufPrint(&self.display_buf, "{d:.2}", .{value}) catch {
                self.display_buf[0] = '?';
                self.display_len = 1;
                return self.display_buf[0..1];
            };
            self.display_len = result.len;
        }
        return self.display_buf[0..self.display_len];
    }
};

/// Number input with value display and vertically-stacked +/- buttons to its right.
/// Click the value to type a number directly. Enter confirms, Escape cancels.
/// Returns true if value changed.
pub fn numberInput(comptime label: []const u8, value: *f32, state: *NumberInputState, opts: NumberInputOpts) bool {
    const old = value.*;
    const up_id = clay.ElementId.localID(label ++ "__ni_up");
    const dn_id = clay.ElementId.localID(label ++ "__ni_dn");
    const val_id = clay.ElementId.localID(label ++ "__ni_val");

    // Check hover outside the closure so we can use the results after
    const dn_hover = clay.pointerOver(dn_id);
    const up_hover = clay.pointerOver(up_id);
    const val_hover = clay.pointerOver(val_id);

    // Handle text editing input
    if (state.editing) {
        if (key_enter) {
            state.commit(value, opts);
        } else if (key_escape) {
            state.cancel();
        } else {
            if (key_backspace) state.deleteChar();
            for (char_buf[0..char_count]) |c| {
                if ((c >= '0' and c <= '9') or c == '.') {
                    state.appendChar(c);
                }
            }
            // Any typing resets the blink timer so cursor stays visible while typing
            if (key_backspace or char_count > 0) {
                state.blink_start = frame_time_ms;
            }
        }
    }

    // Click on value box to start editing; click elsewhere to commit
    if (val_hover and mouseReleased() and !state.editing) {
        state.startEditing(value.*, opts.as_percent);
    } else if (!val_hover and mouseReleased() and state.editing) {
        state.commit(value, opts);
    }

    const half_btn = opts.btn_size * 0.5;
    const btn_fs: u16 = @intFromFloat(@max(8, @round(@as(f32, @floatFromInt(opts.font_size)) * 0.7)));

    clay.UI()(.{
        .id = clay.ElementId.localID(label ++ "__ni_row"),
        .layout = .{
            .direction = .left_to_right,
            .child_gap = 4,
            .child_alignment = .{ .y = .center },
        },
    })({
        // Label
        clay.text(label, .{
            .font_size = opts.font_size,
            .color = theme.text_primary,
        });

        // Value display / edit box
        const val_str = state.formatDisplay(value.*, opts);
        const border_color = if (state.editing) theme.neon else theme.border_default;
        // When all text is selected, show a highlight background behind the text
        const text_bg = if (state.editing and state.selected_all)
            theme.neon_subtle
        else if (state.editing)
            theme.frame_bg_hover
        else
            theme.frame_bg;

        clay.UI()(.{
            .id = val_id,
            .layout = .{
                .sizing = .{ .w = .fixed(opts.display_width), .h = .fixed(opts.btn_size) },
                .child_alignment = .{ .x = .center, .y = .center },
            },
            .background_color = text_bg,
            .corner_radius = .all(4),
            .border = .{ .color = border_color, .width = .outside(1) },
        })({
            clay.text(val_str, .{
                .font_size = opts.font_size,
                .color = if (state.editing and state.selected_all) theme.text_primary else theme.neon,
            });
        });

        // Vertically stacked +/- buttons
        clay.UI()(.{
            .id = clay.ElementId.localID(label ++ "__ni_btns"),
            .layout = .{
                .direction = .top_to_bottom,
                .child_gap = 1,
            },
        })({
            // Up (+) button
            clay.UI()(.{
                .id = up_id,
                .layout = .{
                    .sizing = .{ .w = .fixed(opts.btn_size), .h = .fixed(half_btn) },
                    .child_alignment = .{ .x = .center, .y = .center },
                },
                .background_color = if (up_hover and mouse_down) theme.button_active else if (up_hover) theme.button_hover else theme.button_default,
                .corner_radius = .all(3),
            })({
                clay.text("+", .{ .font_size = btn_fs, .color = theme.text_primary });
            });

            // Down (-) button
            clay.UI()(.{
                .id = dn_id,
                .layout = .{
                    .sizing = .{ .w = .fixed(opts.btn_size), .h = .fixed(half_btn) },
                    .child_alignment = .{ .x = .center, .y = .center },
                },
                .background_color = if (dn_hover and mouse_down) theme.button_active else if (dn_hover) theme.button_hover else theme.button_default,
                .corner_radius = .all(3),
            })({
                clay.text("-", .{ .font_size = btn_fs, .color = theme.text_primary });
            });
        });
    });

    if (!state.editing) {
        if (dn_hover and mouseReleased()) {
            value.* = @max(opts.min, value.* - opts.step);
        }
        if (up_hover and mouseReleased()) {
            value.* = @min(opts.max, value.* + opts.step);
        }
    }

    return value.* != old;
}
