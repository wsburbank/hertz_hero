const std = @import("std");
const clay = @import("clay");
const midi = @import("midi.zig");
const music_theory = @import("music_theory.zig");
const playback = @import("playback.zig");
const main_mod = @import("main.zig");
const theme = @import("theme.zig");

// ============================================================================
// Custom DrawList — replaces zgui.DrawList
// ============================================================================

pub const LinePrimitive = struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    color: u32,
    thickness: f32,
};

pub const CirclePrimitive = struct {
    cx: f32,
    cy: f32,
    radius: f32,
    color: u32,
    thickness: f32,
};

pub const FilledCirclePrimitive = struct {
    cx: f32,
    cy: f32,
    radius: f32,
    color: u32,
};

pub const RectPrimitive = struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    color: u32,
};

pub const FilledRectPrimitive = struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    color: u32,
};

pub const TextPrimitive = struct {
    x: f32,
    y: f32,
    color: u32,
    text: [64]u8,
    text_len: usize,
};

const MAX_LINES = 65536;
const MAX_CIRCLES = 16384;
const MAX_FILLED_CIRCLES = 32768;
const MAX_RECTS = 8192;
const MAX_FILLED_RECTS = 16384;
const MAX_TEXTS = 8192;

pub const DrawList = struct {
    lines: [MAX_LINES]LinePrimitive = undefined,
    line_count: usize = 0,
    circles: [MAX_CIRCLES]CirclePrimitive = undefined,
    circle_count: usize = 0,
    filled_circles: [MAX_FILLED_CIRCLES]FilledCirclePrimitive = undefined,
    filled_circle_count: usize = 0,
    rects: [MAX_RECTS]RectPrimitive = undefined,
    rect_count: usize = 0,
    filled_rects: [MAX_FILLED_RECTS]FilledRectPrimitive = undefined,
    filled_rect_count: usize = 0,
    texts: [MAX_TEXTS]TextPrimitive = undefined,
    text_count: usize = 0,

    pub fn clear(self: *DrawList) void {
        self.line_count = 0;
        self.circle_count = 0;
        self.filled_circle_count = 0;
        self.rect_count = 0;
        self.filled_rect_count = 0;
        self.text_count = 0;
    }

    pub fn addLine(self: *DrawList, x1: f32, y1: f32, x2: f32, y2: f32, color: u32, thickness: f32) void {
        if (self.line_count >= MAX_LINES) return;
        self.lines[self.line_count] = .{ .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2, .color = color, .thickness = thickness };
        self.line_count += 1;
    }

    pub fn addCircle(self: *DrawList, cx: f32, cy: f32, radius: f32, color: u32, thickness: f32) void {
        if (self.circle_count >= MAX_CIRCLES) return;
        self.circles[self.circle_count] = .{ .cx = cx, .cy = cy, .radius = radius, .color = color, .thickness = thickness };
        self.circle_count += 1;
    }

    pub fn addCircleFilled(self: *DrawList, cx: f32, cy: f32, radius: f32, color: u32) void {
        if (self.filled_circle_count >= MAX_FILLED_CIRCLES) return;
        self.filled_circles[self.filled_circle_count] = .{ .cx = cx, .cy = cy, .radius = radius, .color = color };
        self.filled_circle_count += 1;
    }

    pub fn addRect(self: *DrawList, x1: f32, y1: f32, x2: f32, y2: f32, color: u32) void {
        if (self.rect_count >= MAX_RECTS) return;
        self.rects[self.rect_count] = .{ .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2, .color = color };
        self.rect_count += 1;
    }

    pub fn addRectFilled(self: *DrawList, x1: f32, y1: f32, x2: f32, y2: f32, color: u32) void {
        if (self.filled_rect_count >= MAX_FILLED_RECTS) return;
        self.filled_rects[self.filled_rect_count] = .{ .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2, .color = color };
        self.filled_rect_count += 1;
    }

    pub fn addText(self: *DrawList, x: f32, y: f32, color: u32, text: []const u8) void {
        if (self.text_count >= MAX_TEXTS) return;
        var prim = TextPrimitive{ .x = x, .y = y, .color = color, .text = undefined, .text_len = @min(text.len, 64) };
        @memcpy(prim.text[0..prim.text_len], text[0..prim.text_len]);
        self.texts[self.text_count] = prim;
        self.text_count += 1;
    }
};

// ============================================================================
// Render state
// ============================================================================

pub const RenderState = struct {
    scroll_x: f32 = 0,
    zoom: f32 = 1.0,
    show_note_labels: bool = false,
    show_master_staff: bool = true,
};

// ============================================================================
// Constants — same as original
// ============================================================================

const base_ppb: f32 = 60.0;
const base_ls: f32 = 10.0;
pub const base_staff_height: f32 = 120.0;
pub const base_master_height: f32 = 180.0;
pub const collapsed_track_height: f32 = 30.0;
const base_left_margin: f32 = 40.0; // reduced: track panel is now separate
const base_clef_w: f32 = 30.0;
const base_nr: f32 = 4.5;
const base_stem_len: f32 = 30.0;
pub const score_top_margin: f32 = 30.0;

pub fn tickToPixelX(tick: u32, tpq: u16, zoom: f32, s: f32) f32 {
    const beats = @as(f32, @floatFromInt(tick)) / @as(f32, @floatFromInt(tpq));
    return base_left_margin * s + base_clef_w * s + beats * base_ppb * zoom * s;
}

fn pitchToStaffY(pitch: u7, clef: music_theory.Clef, s: f32) f32 {
    const dmap = [12]u8{ 0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6 };
    const p: u16 = @intCast(pitch);
    const dstep = (p / 12) * 7 + dmap[p % 12];
    const ref: f32 = switch (clef) {
        .treble => 41.0,
        .bass => 29.0,
    };
    return (ref - @as(f32, @floatFromInt(dstep))) * base_ls * s / 2.0;
}

fn needsLedgerCount(pitch: u7, clef: music_theory.Clef) struct { count: i8, above: bool } {
    const dmap = [12]u8{ 0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6 };
    const p: u16 = @intCast(pitch);
    const step: i16 = @intCast((p / 12) * 7 + dmap[p % 12]);
    switch (clef) {
        .treble => {
            if (step < 37) return .{ .count = @intCast(@divTrunc(37 - step + 1, 2)), .above = false };
            if (step > 45) return .{ .count = @intCast(@divTrunc(step - 45 + 1, 2)), .above = true };
        },
        .bass => {
            if (step < 25) return .{ .count = @intCast(@divTrunc(25 - step + 1, 2)), .above = false };
            if (step > 33) return .{ .count = @intCast(@divTrunc(step - 33 + 1, 2)), .above = true };
        },
    }
    return .{ .count = 0, .above = false };
}

// ============================================================================
// Score drawing — called from Clay custom element callback
// ============================================================================

/// Custom data passed through Clay custom element to the renderer
pub const ScoreRenderData = struct {
    model: *music_theory.NotationModel,
    song: *midi.Song,
    state: *const RenderState,
    player: *const playback.PlaybackEngine,
    track_states: *const [main_mod.MAX_TRACKS]main_mod.TrackDisplayState,
    ui_scale: f32,
    scroll_y: f32,
};

/// Global draw list — populated during custom draw callback, rendered by clay_renderer
pub var draw_list: DrawList = .{};

/// Called by clay_renderer when it encounters a custom render command
pub fn drawScoreCustom(
    bbox: clay.BoundingBox,
    custom_data: ?*anyopaque,
    _: ?*anyopaque,
) void {
    const data: *ScoreRenderData = @ptrCast(@alignCast(custom_data orelse return));
    draw_list.clear();

    drawScoreContent(
        &draw_list,
        data.model,
        data.song,
        data.state,
        bbox,
        data.player,
        data.track_states,
        data.ui_scale,
        data.scroll_y,
    );
}

fn drawScoreContent(
    dl: *DrawList,
    model: *music_theory.NotationModel,
    song: *midi.Song,
    state: *const RenderState,
    bbox: clay.BoundingBox,
    player: *const playback.PlaybackEngine,
    track_states: *const [main_mod.MAX_TRACKS]main_mod.TrackDisplayState,
    s: f32,
    scroll_y: f32,
) void {
    const ox = bbox.x;
    const win_w = bbox.width;
    const tpq = song.ticks_per_quarter;
    const lm = base_left_margin * s;
    const sh = base_staff_height * s;
    const mh = base_master_height * s;

    var total_staves: f32 = 0;
    for (model.staves) |_| total_staves += 1;
    const total_h = (if (state.show_master_staff) mh else 0) + total_staves * sh + sh;
    _ = total_h;

    const oy = bbox.y + 30 * s - scroll_y;
    var current_y: f32 = oy;

    const vis_top = bbox.y;
    const vis_bot = bbox.y + bbox.height;

    // Master staff
    if (state.show_master_staff) {
        if (current_y + mh > vis_top and current_y < vis_bot) {
            drawMasterStaff(dl, model, song, state, ox, current_y, win_w, player, track_states, s);
        }
        current_y += mh;
    }

    // Per-track staves
    for (model.staves) |staff| {
        const sy = current_y;
        const track_idx: usize = @intCast(@min(staff.track_index, main_mod.MAX_TRACKS - 1));

        // Collapsed tracks: reserve compact space but don't draw
        if (!track_states[track_idx].expanded) {
            current_y += collapsed_track_height * s;
            continue;
        }

        if (sy > vis_bot + sh) break;
        if (sy + sh < vis_top) {
            current_y += sh;
            continue;
        }

        const is_muted = track_states[track_idx].muted;
        const line_sp = base_ls * s;
        const music_ox = ox + lm;

        // Full-width bordered row — aligned with track panel rows [sy, sy+sh]
        const bg_col: u32 = if (track_idx % 2 == 0) theme.col_track_bg_even else theme.col_track_bg_odd;
        dl.addRectFilled(ox, sy, ox + win_w, sy + sh, bg_col);
        dl.addRect(ox, sy, ox + win_w, sy + sh, theme.col_track_border);

        // Staff center — vertically centered within the [sy, sy+sh] box
        const staff_cy = sy + sh * 0.5;

        // Staff lines
        var li: i8 = -2;
        while (li <= 2) : (li += 1) {
            const y = staff_cy + @as(f32, @floatFromInt(li)) * line_sp;
            const line_col: u32 = if (is_muted) 0xFF333344 else theme.col_line;
            dl.addLine(music_ox, y, music_ox + win_w - lm, y, line_col, 1.0);
        }

        // Clef label
        const ct: []const u8 = if (staff.clef == .treble) "G" else "F";
        dl.addText(music_ox + 5, staff_cy - 8 * s, theme.col_clef, ct);

        // Barlines
        for (model.measures) |meas| {
            const bx = tickToPixelX(meas.tick_start, tpq, state.zoom, s) - state.scroll_x + ox;
            if (bx < music_ox - 10 or bx > ox + win_w + 10) continue;
            dl.addLine(bx, staff_cy - 2 * line_sp, bx, staff_cy + 2 * line_sp, theme.col_bar, 1.0);
        }

        // Notes
        if (!is_muted) {
            drawNotes(dl, staff.notes, staff.clef, tpq, state, ox, staff_cy, win_w, player, s);
        }

        current_y += sh;
    }

    // Playback cursor
    if (player.state == .playing or player.current_tick > 0) {
        const cx = tickToPixelX(player.current_tick, tpq, state.zoom, s) - state.scroll_x + ox;
        if (cx >= ox + lm and cx <= ox + win_w) {
            dl.addRectFilled(cx - 1.5 * s, oy - 10, cx + 1.5 * s, current_y, theme.col_cursor);
        }
    }
}

fn drawMasterStaff(
    dl: *DrawList,
    model: *music_theory.NotationModel,
    song: *midi.Song,
    state: *const RenderState,
    ox: f32,
    oy: f32,
    win_w: f32,
    player: *const playback.PlaybackEngine,
    track_states: *const [main_mod.MAX_TRACKS]main_mod.TrackDisplayState,
    s: f32,
) void {
    const tpq = song.ticks_per_quarter;
    const lm = base_left_margin * s;
    const music_ox = ox + lm;
    const line_sp = base_ls * s;

    // "Master" label
    dl.addText(ox + 5, oy - 10 * s, theme.col_master_label, "Master");

    // Treble staff
    const treble_y = oy + 20 * s;
    drawStaffLines(dl, music_ox, treble_y, win_w - lm, theme.col_master_line, s);
    dl.addText(music_ox + 5, treble_y - 8 * s, theme.col_master_label, "G");

    // Bass staff
    const bass_y = treble_y + 60 * s;
    drawStaffLines(dl, music_ox, bass_y, win_w - lm, theme.col_master_line, s);
    dl.addText(music_ox + 5, bass_y - 8 * s, theme.col_master_label, "F");

    // Barlines
    for (model.measures) |meas| {
        const bx = tickToPixelX(meas.tick_start, tpq, state.zoom, s) - state.scroll_x + ox;
        if (bx < music_ox - 10 or bx > ox + win_w + 10) continue;
        dl.addLine(bx, treble_y - 2 * line_sp, bx, bass_y + 2 * line_sp, theme.col_bar, 1.0);
    }

    // Notes from included tracks
    for (model.staves) |staff| {
        const track_idx: usize = @intCast(@min(staff.track_index, main_mod.MAX_TRACKS - 1));
        if (!track_states[track_idx].expanded) continue;
        if (!track_states[track_idx].include_in_master) continue;
        if (track_states[track_idx].muted) continue;

        for (staff.notes) |note| {
            const nx = tickToPixelX(note.snapped_tick_on, tpq, state.zoom, s) - state.scroll_x + ox;
            if (nx < music_ox - 20 or nx > ox + win_w + 20) continue;

            const use_treble = note.pitch >= 60;
            const staff_y = if (use_treble) treble_y else bass_y;
            const clef: music_theory.Clef = if (use_treble) .treble else .bass;
            const ny = staff_y + pitchToStaffY(note.pitch, clef, s);

            const playing = player.state == .playing and
                player.current_tick >= note.snapped_tick_on and
                player.current_tick < note.snapped_tick_off;

            drawSingleNote(dl, note, nx, ny, note.pitch, playing, tpq, state, ox, s);
        }
    }
}

fn drawStaffLines(dl: *DrawList, x: f32, center_y: f32, width: f32, color: u32, s: f32) void {
    const line_sp = base_ls * s;
    var li: i8 = -2;
    while (li <= 2) : (li += 1) {
        const y = center_y + @as(f32, @floatFromInt(li)) * line_sp;
        dl.addLine(x, y, x + width, y, color, 1.0);
    }
}

fn drawNotes(
    dl: *DrawList,
    notes: []const music_theory.QuantizedNote,
    clef: music_theory.Clef,
    tpq: u16,
    state: *const RenderState,
    ox: f32,
    sy: f32,
    win_w: f32,
    player: *const playback.PlaybackEngine,
    s: f32,
) void {
    const music_ox = ox + base_left_margin * s;
    const note_r = base_nr * s;
    const line_sp = base_ls * s;

    for (notes) |note| {
        const nx = tickToPixelX(note.snapped_tick_on, tpq, state.zoom, s) - state.scroll_x + ox;
        if (nx < music_ox - 20 or nx > ox + win_w + 20) continue;

        const ny = sy + pitchToStaffY(note.pitch, clef, s);
        const playing = player.state == .playing and
            player.current_tick >= note.snapped_tick_on and
            player.current_tick < note.snapped_tick_off;

        // Ledger lines
        const ledger = needsLedgerCount(note.pitch, clef);
        if (ledger.count > 0) {
            var lj: i8 = 0;
            while (lj < ledger.count) : (lj += 1) {
                const ly = if (ledger.above)
                    sy - 2 * line_sp - @as(f32, @floatFromInt(lj + 1)) * line_sp
                else
                    sy + 2 * line_sp + @as(f32, @floatFromInt(lj + 1)) * line_sp;
                dl.addLine(nx - note_r * 2, ly, nx + note_r * 2, ly, theme.col_line, 1.0);
            }
        }

        drawSingleNote(dl, note, nx, ny, note.pitch, playing, tpq, state, ox, s);

        // Note label
        if (state.show_note_labels) {
            var buf: [4]u8 = undefined;
            const lbl = note.spelled.label(&buf);
            dl.addText(nx - 5 * s, ny - 15 * s, theme.col_label, lbl);
        }
    }
}

fn drawSingleNote(
    dl: *DrawList,
    note: music_theory.QuantizedNote,
    nx: f32,
    ny: f32,
    pitch: u7,
    playing: bool,
    tpq: u16,
    state: *const RenderState,
    ox: f32,
    s: f32,
) void {
    const note_r = base_nr * s;
    const active_nr = if (playing) note_r * 1.3 else note_r;

    // Playing emphasis
    if (playing) {
        const off_x = tickToPixelX(note.snapped_tick_off, tpq, state.zoom, s) - state.scroll_x + ox;
        dl.addRectFilled(nx, ny - 3 * s, off_x, ny + 3 * s, theme.col_play_bar);
        dl.addCircleFilled(nx, ny, note_r * 2.5, theme.col_play_glow);
    }

    const nc: u32 = if (playing) theme.col_play else theme.col_note;

    // Note head
    switch (note.duration_type) {
        .whole => {
            dl.addCircle(nx, ny, active_nr, nc, 1.5 * s);
        },
        .half => {
            dl.addCircle(nx, ny, active_nr, nc, 1.5 * s);
            drawStem(dl, nx, ny, pitch, s);
        },
        else => {
            dl.addCircleFilled(nx, ny, active_nr, nc);
            drawStem(dl, nx, ny, pitch, s);
            drawFlags(dl, nx, ny, pitch, note.duration_type, s);
        },
    }

    // Dot
    if (note.is_dotted) {
        dl.addCircleFilled(nx + note_r * 2.5, ny - 2 * s, 2.0 * s, nc);
    }
}

fn drawStem(dl: *DrawList, x: f32, y: f32, pitch: u7, s: f32) void {
    const note_r = base_nr * s;
    const stem = base_stem_len * s;
    if (pitch >= 71) {
        dl.addLine(x - note_r, y, x - note_r, y + stem, theme.col_stem, 1.0);
    } else {
        dl.addLine(x + note_r, y, x + note_r, y - stem, theme.col_stem, 1.0);
    }
}

fn drawFlags(dl: *DrawList, x: f32, y: f32, pitch: u7, dur: music_theory.DurationType, s: f32) void {
    const nf: u8 = switch (dur) {
        .eighth => 1,
        .sixteenth => 2,
        .thirty_second => 3,
        else => return,
    };
    const note_r = base_nr * s;
    const stem = base_stem_len * s;
    const up = pitch < 71;
    var fi: u8 = 0;
    while (fi < nf) : (fi += 1) {
        const fo = @as(f32, @floatFromInt(fi)) * 6.0 * s;
        if (up) {
            dl.addLine(x + note_r, y - stem + fo, x + note_r + 8 * s, y - stem + fo + 10 * s, theme.col_stem, 1.5 * s);
        } else {
            dl.addLine(x - note_r, y + stem - fo, x - note_r - 8 * s, y + stem - fo - 10 * s, theme.col_stem, 1.5 * s);
        }
    }
}
