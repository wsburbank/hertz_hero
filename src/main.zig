const std = @import("std");
const zglfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const clay = @import("clay");

const midi = @import("midi.zig");
const music_theory = @import("music_theory.zig");
const playback = @import("playback.zig");
const file_dialog = @import("file_dialog.zig");
const font_mod = @import("font.zig");
const clay_renderer = @import("clay_renderer.zig");
const theme = @import("theme.zig");
const widgets = @import("widgets.zig");
const score_renderer = @import("renderer.zig");

const window_title = "Hertz Hero";
const default_width: c_int = 1920;
const default_height: c_int = 1080;

pub const TrackDisplayState = struct {
    muted: bool = false,
    expanded: bool = true, // when collapsed, staff is hidden from score
    volume: f32 = 1.0, // per-track slider (velocity scaling), default 1.0
    base_volume: f32 = 1.0, // balance-derived level (CC7), set by blend slider
    initial_vol: f32 = 1.0, // volume from MIDI CC7*CC11 (original mix)
    balanced_vol: f32 = 1.0, // volume from RMS auto-balance
    include_in_master: bool = false,
    program: i32 = 0,
    channel: i32 = -1,
    last_sent_base_vol: f32 = -1.0, // tracks CC7 changes
    last_sent_expression: f32 = -1.0, // tracks CC11 changes
    last_sent_program: i32 = -1,
    volume_slider: widgets.SliderState = .{},
    instrument_combo: widgets.ComboState = .{},
};

pub const MAX_TRACKS = 16;

pub const RenderState = struct {
    scroll_x: f32 = 0,
    ui_zoom: f32 = 2.0, // scales UI text/padding (not music)
    music_scale: f32 = 3.0, // scales sheet music rendering
    show_note_labels: bool = false,
    show_master_staff: bool = true,

    // Balance blend: 0.0 = original MIDI mix, 1.0 = full auto-balance
    balance_blend: f32 = 0.0,

    // Widget slider states
    bpm_slider: widgets.SliderState = .{},
    scale_slider: widgets.SliderState = .{},
    hscroll_slider: widgets.SliderState = .{},
    balance_slider: widgets.SliderState = .{},
    zoom_input: widgets.NumberInputState = .{},
};

// General MIDI instrument names as a comptime array of string slices
const gm_instruments = blk: {
    @setEvalBranchQuota(10000);
    const raw =
        "0 Acoustic Grand Piano\x00" ++
        "1 Bright Acoustic Piano\x00" ++
        "2 Electric Grand Piano\x00" ++
        "3 Honky-tonk Piano\x00" ++
        "4 Electric Piano 1\x00" ++
        "5 Electric Piano 2\x00" ++
        "6 Harpsichord\x00" ++
        "7 Clavinet\x00" ++
        "8 Celesta\x00" ++
        "9 Glockenspiel\x00" ++
        "10 Music Box\x00" ++
        "11 Vibraphone\x00" ++
        "12 Marimba\x00" ++
        "13 Xylophone\x00" ++
        "14 Tubular Bells\x00" ++
        "15 Dulcimer\x00" ++
        "16 Drawbar Organ\x00" ++
        "17 Percussive Organ\x00" ++
        "18 Rock Organ\x00" ++
        "19 Church Organ\x00" ++
        "20 Reed Organ\x00" ++
        "21 Accordion\x00" ++
        "22 Harmonica\x00" ++
        "23 Tango Accordion\x00" ++
        "24 Nylon Guitar\x00" ++
        "25 Steel Guitar\x00" ++
        "26 Jazz Guitar\x00" ++
        "27 Clean Guitar\x00" ++
        "28 Muted Guitar\x00" ++
        "29 Overdriven Guitar\x00" ++
        "30 Distortion Guitar\x00" ++
        "31 Guitar Harmonics\x00" ++
        "32 Acoustic Bass\x00" ++
        "33 Finger Bass\x00" ++
        "34 Pick Bass\x00" ++
        "35 Fretless Bass\x00" ++
        "36 Slap Bass 1\x00" ++
        "37 Slap Bass 2\x00" ++
        "38 Synth Bass 1\x00" ++
        "39 Synth Bass 2\x00" ++
        "40 Violin\x00" ++
        "41 Viola\x00" ++
        "42 Cello\x00" ++
        "43 Contrabass\x00" ++
        "44 Tremolo Strings\x00" ++
        "45 Pizzicato Strings\x00" ++
        "46 Orchestral Harp\x00" ++
        "47 Timpani\x00" ++
        "48 String Ensemble 1\x00" ++
        "49 String Ensemble 2\x00" ++
        "50 Synth Strings 1\x00" ++
        "51 Synth Strings 2\x00" ++
        "52 Choir Aahs\x00" ++
        "53 Voice Oohs\x00" ++
        "54 Synth Voice\x00" ++
        "55 Orchestra Hit\x00" ++
        "56 Trumpet\x00" ++
        "57 Trombone\x00" ++
        "58 Tuba\x00" ++
        "59 Muted Trumpet\x00" ++
        "60 French Horn\x00" ++
        "61 Brass Section\x00" ++
        "62 Synth Brass 1\x00" ++
        "63 Synth Brass 2\x00" ++
        "64 Soprano Sax\x00" ++
        "65 Alto Sax\x00" ++
        "66 Tenor Sax\x00" ++
        "67 Baritone Sax\x00" ++
        "68 Oboe\x00" ++
        "69 English Horn\x00" ++
        "70 Bassoon\x00" ++
        "71 Clarinet\x00" ++
        "72 Piccolo\x00" ++
        "73 Flute\x00" ++
        "74 Recorder\x00" ++
        "75 Pan Flute\x00" ++
        "76 Blown Bottle\x00" ++
        "77 Shakuhachi\x00" ++
        "78 Whistle\x00" ++
        "79 Ocarina\x00" ++
        "80 Lead 1 (Square)\x00" ++
        "81 Lead 2 (Sawtooth)\x00" ++
        "82 Lead 3 (Calliope)\x00" ++
        "83 Lead 4 (Chiff)\x00" ++
        "84 Lead 5 (Charang)\x00" ++
        "85 Lead 6 (Voice)\x00" ++
        "86 Lead 7 (Fifths)\x00" ++
        "87 Lead 8 (Bass+Lead)\x00" ++
        "88 Pad 1 (New Age)\x00" ++
        "89 Pad 2 (Warm)\x00" ++
        "90 Pad 3 (Polysynth)\x00" ++
        "91 Pad 4 (Choir)\x00" ++
        "92 Pad 5 (Bowed)\x00" ++
        "93 Pad 6 (Metallic)\x00" ++
        "94 Pad 7 (Halo)\x00" ++
        "95 Pad 8 (Sweep)\x00" ++
        "96 FX 1 (Rain)\x00" ++
        "97 FX 2 (Soundtrack)\x00" ++
        "98 FX 3 (Crystal)\x00" ++
        "99 FX 4 (Atmosphere)\x00" ++
        "100 FX 5 (Brightness)\x00" ++
        "101 FX 6 (Goblins)\x00" ++
        "102 FX 7 (Echoes)\x00" ++
        "103 FX 8 (Sci-Fi)\x00" ++
        "104 Sitar\x00" ++
        "105 Banjo\x00" ++
        "106 Shamisen\x00" ++
        "107 Koto\x00" ++
        "108 Kalimba\x00" ++
        "109 Bagpipe\x00" ++
        "110 Fiddle\x00" ++
        "111 Shanai\x00" ++
        "112 Tinkle Bell\x00" ++
        "113 Agogo\x00" ++
        "114 Steel Drums\x00" ++
        "115 Woodblock\x00" ++
        "116 Taiko Drum\x00" ++
        "117 Melodic Tom\x00" ++
        "118 Synth Drum\x00" ++
        "119 Reverse Cymbal\x00" ++
        "120 Guitar Fret Noise\x00" ++
        "121 Breath Noise\x00" ++
        "122 Seashore\x00" ++
        "123 Bird Tweet\x00" ++
        "124 Telephone Ring\x00" ++
        "125 Helicopter\x00" ++
        "126 Applause\x00" ++
        "127 Gunshot\x00";

    var result: [128][]const u8 = undefined;
    var start: usize = 0;
    var idx: usize = 0;
    for (raw, 0..) |ch, i| {
        if (ch == 0) {
            result[idx] = raw[start..i];
            idx += 1;
            start = i + 1;
        }
    }
    break :blk result;
};

// Scroll wheel accumulator — written by GLFW callback, consumed each frame
var scroll_y_accum: f32 = 0;

fn scrollCallback(_: *zglfw.Window, _: f64, yoffset: f64) callconv(.c) void {
    scroll_y_accum += @floatCast(yoffset);
}

fn charCallback(_: *zglfw.Window, codepoint: u32) callconv(.c) void {
    widgets.pushChar(codepoint);
}

fn keyCallback(_: *zglfw.Window, key: zglfw.Key, _: c_int, action: zglfw.Action, _: zglfw.Mods) callconv(.c) void {
    if (action == .press or action == .repeat) {
        if (key == .backspace) widgets.pushKey(.backspace);
        if (key == .enter or key == .kp_enter) widgets.pushKey(.enter);
        if (key == .escape) widgets.pushKey(.escape);
    }
}

/// Initialize track display states from parsed MIDI data.
/// Computes both the initial (CC7*CC11) and auto-balanced (RMS) volumes per track.
/// The balance_blend slider in RenderState interpolates between them.
fn initTrackStatesFromSong(s: *midi.Song, track_states: *[MAX_TRACKS]TrackDisplayState) void {
    for (s.tracks, 0..) |track, ti| {
        if (ti >= MAX_TRACKS) break;
        if (track.program) |prog| track_states[ti].program = @intCast(prog);
        if (track.channel) |ch| track_states[ti].channel = @intCast(ch);

        // Compute initial volume from CC7 and CC11
        // CC7 (volume) defaults to 100/127 per GM spec when not specified
        // CC11 (expression) defaults to 127/127 per GM spec when not specified
        const cc7_f: f32 = if (track.initial_volume_cc7) |v| @as(f32, @floatFromInt(v)) / 127.0 else 100.0 / 127.0;
        const cc11_f: f32 = if (track.initial_expression_cc11) |v| @as(f32, @floatFromInt(v)) / 127.0 else 1.0;
        track_states[ti].initial_vol = cc7_f * cc11_f;
    }

    // Compute auto-balanced volumes from RMS velocity
    computeBalancedVolumes(s, track_states);

    // Start at the original mix (blend = 0): base_volume from CC7, per-track slider at 1.0
    for (track_states) |*ts| {
        ts.base_volume = ts.initial_vol;
        ts.volume = 1.0;
        ts.last_sent_base_vol = -1.0;
    }
}

/// Compute the auto-balanced volume targets using RMS velocity normalization.
fn computeBalancedVolumes(s: *midi.Song, track_states: *[MAX_TRACKS]TrackDisplayState) void {
    const track_count = @min(s.tracks.len, MAX_TRACKS);
    if (track_count == 0) return;

    // Find the median RMS velocity among tracks that have notes
    var rms_values: [MAX_TRACKS]f32 = undefined;
    var active_count: usize = 0;
    for (s.tracks[0..track_count]) |track| {
        if (track.notes.len > 0 and track.rms_velocity > 0) {
            rms_values[active_count] = track.rms_velocity;
            active_count += 1;
        }
    }
    if (active_count == 0) {
        for (track_states[0..track_count]) |*ts| ts.balanced_vol = ts.initial_vol;
        return;
    }

    std.mem.sort(f32, rms_values[0..active_count], {}, std.sort.asc(f32));
    const target_rms = rms_values[active_count / 2];

    for (s.tracks[0..track_count], 0..) |track, ti| {
        if (track.notes.len == 0 or track.rms_velocity < 1.0) {
            track_states[ti].balanced_vol = track_states[ti].initial_vol;
            continue;
        }
        const gain = target_rms / track.rms_velocity;
        track_states[ti].balanced_vol = @min(3.0, @max(0.05, gain));
    }
}

/// Linearly interpolate base_volume between initial and balanced (CC7 level).
/// Does NOT touch the per-track volume slider.
fn applyBalanceBlend(track_states: *[MAX_TRACKS]TrackDisplayState, blend: f32) void {
    const t = @min(1.0, @max(0.0, blend));
    for (track_states) |*ts| {
        ts.base_volume = ts.initial_vol + (ts.balanced_vol - ts.initial_vol) * t;
        ts.last_sent_base_vol = -1.0;
    }
}

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa_impl.deinit();
    const allocator = gpa_impl.allocator();

    // Initialize GLFW
    try zglfw.init();
    defer zglfw.terminate();

    zglfw.windowHint(.context_version_major, 3);
    zglfw.windowHint(.context_version_minor, 3);
    zglfw.windowHint(.opengl_profile, .opengl_core_profile);

    const window = try zglfw.createWindow(default_width, default_height, window_title, null, null);
    defer zglfw.destroyWindow(window);

    zglfw.makeContextCurrent(window);
    zglfw.swapInterval(1);
    _ = window.setScrollCallback(scrollCallback);
    _ = window.setCharCallback(charCallback);
    _ = window.setKeyCallback(keyCallback);

    try zopengl.loadCoreProfile(@ptrCast(&zglfw.getProcAddress), 3, 3);

    // Initialize font system
    var font_ctx = font_mod.FontContext.init();
    defer font_ctx.deinit();
    font_ctx.loadFont(0, "C:/Windows/Fonts/segoeui.ttf", 48.0) catch |err| {
        std.debug.print("Failed to load font: {}\n", .{err});
    };

    // Initialize Clay
    const clay_mem_size = clay.minMemorySize();
    const clay_mem = try allocator.alloc(u8, clay_mem_size);
    defer allocator.free(clay_mem);
    const clay_arena = clay.Arena.init(clay_mem);
    _ = clay.initialize(
        clay_arena,
        .{ .w = @floatFromInt(default_width), .h = @floatFromInt(default_height) },
        .{},
    );
    clay.setMeasureTextFunction(*font_mod.FontContext, &font_ctx, font_mod.FontContext.measureText);

    // Initialize Clay renderer
    var clay_ren = clay_renderer.ClayRenderer.init(&font_ctx);
    defer clay_ren.deinit();

    // Initialize DrawList renderer for sheet music
    var dl_renderer = clay_renderer.DrawListRenderer.init(&font_ctx);
    defer dl_renderer.deinit();

    // Wire up custom draw callback
    clay_ren.custom_draw_fn = &customDrawCallback;
    clay_ren.custom_draw_user_data = @ptrCast(&dl_renderer);

    // Application state
    var song: ?midi.Song = null;
    defer if (song != null) song.?.deinit();

    var notation: ?music_theory.NotationModel = null;
    defer if (notation != null) notation.?.deinit();

    var track_states: [MAX_TRACKS]TrackDisplayState = [_]TrackDisplayState{.{}} ** MAX_TRACKS;

    var player = playback.PlaybackEngine.init();
    player.initAudio();
    defer player.deinit();

    var render_state = RenderState{};

    var midi_path_buf: ?[]const u8 = null;
    defer if (midi_path_buf) |p| allocator.free(p);

    // Auto-load default song
    {
        const default_path = "Music/M83 _ Midnight City .mid";
        song = midi.parseFile(allocator, default_path) catch |err| blk: {
            std.debug.print("Failed to load default MIDI: {}\n", .{err});
            break :blk null;
        };
        if (song) |*s| {
            notation = music_theory.NotationModel.build(allocator, s) catch null;
            player.load(s);
            initTrackStatesFromSong(s, &track_states);
        }
    }

    var last_time: f64 = @floatFromInt(std.time.milliTimestamp());

    // Main loop
    while (!window.shouldClose()) {
        const now: f64 = @floatFromInt(std.time.milliTimestamp());
        const delta_ms = now - last_time;
        last_time = now;

        zglfw.pollEvents();

        const fb_size = window.getFramebufferSize();
        const fb_w: f32 = @floatFromInt(fb_size[0]);
        const fb_h: f32 = @floatFromInt(fb_size[1]);
        gl.viewport(0, 0, fb_size[0], fb_size[1]);
        gl.clearColor(0.06, 0.06, 0.09, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        // Input
        const mouse_pos = window.getCursorPos();
        const mx: f32 = @floatCast(mouse_pos[0]);
        const my: f32 = @floatCast(mouse_pos[1]);
        const mdown = window.getMouseButton(.left) == .press;

        // Feed input to Clay and widgets
        const scroll_dy = scroll_y_accum * 40.0; // scale scroll wheel to pixels
        scroll_y_accum = 0;
        clay.setLayoutDimensions(.{ .w = fb_w, .h = fb_h });
        clay.setPointerState(.{ .x = mx, .y = my }, mdown);
        // Disable drag-scrolling while any slider is being dragged so the
        // scroll container doesn't fight with the slider for pointer ownership.
        clay.updateScrollContainers(!widgets.any_slider_dragging, .{ .x = 0, .y = scroll_dy }, @floatCast(delta_ms / 1000.0));
        widgets.updateInput(mx, my, mdown, scroll_dy, delta_ms);

        // Update playback
        if (song) |*s| {
            player.update(delta_ms / 1000.0, s);
        }

        // Sync track_states -> playback engine
        for (&track_states, 0..) |*ts, i| {
            const idx: u5 = @intCast(@min(i, 15));
            player.track_muted[idx] = ts.muted;
            // Per-track slider controls velocity scaling
            player.track_volumes[idx] = ts.volume;

            if (ts.channel >= 0) {
                const ch: u4 = @intCast(@as(u32, @intCast(ts.channel)) & 0xF);
                // Balance-derived base volume controls CC7
                if (@abs(ts.base_volume - ts.last_sent_base_vol) > 0.01) {
                    playback.PlaybackEngine.setChannelVolume(ch, ts.base_volume);
                    ts.last_sent_base_vol = ts.base_volume;
                }
                // Per-track slider controls CC11 (expression) for immediate effect
                if (@abs(ts.volume - ts.last_sent_expression) > 0.01) {
                    playback.PlaybackEngine.setChannelExpression(ch, ts.volume);
                    ts.last_sent_expression = ts.volume;
                }
                if (ts.program != ts.last_sent_program) {
                    const prog: u7 = @intCast(@as(u32, @intCast(ts.program)) & 0x7F);
                    playback.PlaybackEngine.setProgramChange(ch, prog);
                    ts.last_sent_program = ts.program;
                }
            }
        }

        // Keyboard scroll
        if (window.getKey(.left) == .press) render_state.scroll_x -= 5.0 * render_state.music_scale;
        if (window.getKey(.right) == .press) render_state.scroll_x += 5.0 * render_state.music_scale;

        // ---- Clay layout ----
        widgets.beginLayoutReset();
        clay.beginLayout();

        // Root
        clay.UI()(.{
            .id = clay.ElementId.ID("Root"),
            .layout = .{
                .sizing = .grow,
                .padding = .all(10),
                .child_gap = 8,
                .direction = .top_to_bottom,
            },
            .background_color = theme.bg_window,
        })({
            // Transport controls bar
            drawTransportControls(&player, &song, &render_state, &track_states);

            // File open handling
            // (triggered by button click in transport controls)

            // Main content area
            if (song) |*s| {
                drawSheetMusicArea(s, &notation, &render_state, &player, &track_states, fb_w, fb_h);
            } else {
                drawEmptyState(render_state.ui_zoom);
            }

            // Status bar
            const status_fs: u16 = @intFromFloat(@round(14 * render_state.ui_zoom));
            clay.UI()(.{
                .id = clay.ElementId.ID("StatusBar"),
                .layout = .{
                    .sizing = .{ .w = .grow, .h = .fixed(28) },
                    .padding = .{ .left = 12, .right = 12, .top = 4, .bottom = 4 },
                    .child_alignment = .{ .y = .center },
                },
                .background_color = theme.bg_child,
                .corner_radius = .all(4),
            })({
                if (song) |s| {
                    var buf: [128]u8 = undefined;
                    const dur = midi.Song.totalDurationSeconds(s);
                    const status = std.fmt.bufPrint(&buf, "Tracks: {d} | Duration: {d:.1}s | TPQ: {d}", .{
                        s.tracks.len,
                        dur,
                        s.ticks_per_quarter,
                    }) catch "---";
                    clay.text(status, .{ .font_size = status_fs, .color = theme.text_disabled });
                } else {
                    clay.text("Hertz Hero — Clay UI", .{ .font_size = status_fs, .color = theme.text_disabled });
                }
            });
        });

        const render_commands = clay.endLayout();

        // Check if Open button was flagged
        if (open_file_requested) {
            open_file_requested = false;
            const hwnd = zglfw.getWin32Window(window);
            if (file_dialog.openMidiFile(allocator, hwnd)) |new_path| {
                player.stop();
                if (notation != null) { notation.?.deinit(); notation = null; }
                if (song != null) { song.?.deinit(); song = null; }
                if (midi_path_buf) |old| allocator.free(old);
                midi_path_buf = new_path;

                track_states = [_]TrackDisplayState{.{}} ** MAX_TRACKS;
                render_state.balance_blend = 0.0;

                song = midi.parseFile(allocator, new_path) catch |err| blk: {
                    std.debug.print("Failed to parse MIDI: {}\n", .{err});
                    break :blk null;
                };

                if (song) |*s| {
                    notation = music_theory.NotationModel.build(allocator, s) catch null;
                    player.load(s);
                    initTrackStatesFromSong(s, &track_states);
                }
            }
        }

        // Render
        clay_ren.screen_width = fb_w;
        clay_ren.screen_height = fb_h;
        dl_renderer.screen_width = fb_w;
        dl_renderer.screen_height = fb_h;
        clay_ren.render(render_commands);
        widgets.clearFrameKeys();

        window.swapBuffers();
    }
}

// Flag set by Open button click, processed after endLayout
var open_file_requested: bool = false;

/// Custom draw callback — called by ClayRenderer for custom render commands.
/// Delegates to score_renderer, then renders the draw list.
fn customDrawCallback(
    bbox: clay.BoundingBox,
    custom_data: ?*anyopaque,
    user_data: ?*anyopaque,
) void {
    // First, call score_renderer to populate the draw list
    score_renderer.drawScoreCustom(bbox, custom_data, null);

    // Then render the draw list with OpenGL
    if (user_data) |ptr| {
        const dlr: *clay_renderer.DrawListRenderer = @ptrCast(@alignCast(ptr));
        dlr.render(&score_renderer.draw_list);
    }
}

// Persistent score render data — must survive past endLayout() and into render()
var score_data: score_renderer.ScoreRenderData = undefined;
var score_data_valid: bool = false;
var score_render_state: score_renderer.RenderState = .{};

fn drawTransportControls(player: *playback.PlaybackEngine, song_opt: *?midi.Song, state: *RenderState, track_states: *[MAX_TRACKS]TrackDisplayState) void {
    const z = state.ui_zoom;
    const fs_btn: u16 = @intFromFloat(@round(20 * z));
    const fs_pos: u16 = @intFromFloat(@round(20 * z));
    const btn_h: f32 = 38 * z;
    const btn_w_open: f32 = 90 * z;
    const btn_w: f32 = 80 * z;

    clay.UI()(.{
        .id = clay.ElementId.ID("Transport"),
        .layout = .{
            .sizing = .{ .w = .grow, .h = .fit },
            .padding = .all(10),
            .direction = .top_to_bottom,
            .child_gap = 8,
        },
        .background_color = theme.bg_child,
        .corner_radius = .all(theme.radius_window),
        .border = .{ .color = theme.border_default, .width = .outside(1) },
    })({
        // Row 1: Buttons + position
        clay.UI()(.{
            .id = clay.ElementId.ID("TransportRow1"),
            .layout = .{
                .direction = .left_to_right,
                .child_gap = 8,
                .child_alignment = .{ .y = .center },
            },
        })({
            if (widgets.button("Open", .{ .w = btn_w_open, .h = btn_h, .font_size = fs_btn })) {
                open_file_requested = true;
            }

            if (player.state == .playing) {
                if (widgets.button("Pause", .{ .w = btn_w, .h = btn_h, .font_size = fs_btn })) player.pause();
            } else {
                if (widgets.button("Play", .{ .w = btn_w, .h = btn_h, .font_size = fs_btn })) player.play();
            }

            if (widgets.button("Stop", .{ .w = btn_w, .h = btn_h, .font_size = fs_btn })) player.stop();

            // Position display
            if (song_opt.*) |*s| {
                const pos = player.getMusicalPosition(s);
                var buf: [64]u8 = undefined;
                const pos_str = std.fmt.bufPrint(&buf, "Measure {d}  Beat {d:.1}", .{
                    pos.measure + 1,
                    pos.beat + 1.0,
                }) catch "---";
                clay.text(pos_str, .{ .font_size = fs_pos, .color = theme.neon });
            }
        });

        // Row 2: Sliders
        clay.UI()(.{
            .id = clay.ElementId.ID("TransportRow2"),
            .layout = .{
                .direction = .left_to_right,
                .child_gap = 20,
                .child_alignment = .{ .y = .center },
            },
        })({
            const sl_fs: u16 = @intFromFloat(@round(16 * z));
            const sl_h: f32 = 24 * z;
            _ = widgets.sliderFloat("BPM", &player.tempo_bpm, 40.0, 240.0, &state.bpm_slider, .{ .width = 200 * z, .height = sl_h, .font_size = sl_fs });
            _ = widgets.numberInput("Zoom", &state.ui_zoom, &state.zoom_input, .{ .btn_size = 28 * z, .font_size = sl_fs, .display_width = 60 * z, .step = 0.05, .min = 0.5, .max = 3.0, .as_percent = true });
            _ = widgets.sliderFloat("Scale", &state.music_scale, 0.5, 3.0, &state.scale_slider, .{ .width = 150 * z, .height = sl_h, .font_size = sl_fs });
        });

        // Row 3: Checkboxes
        clay.UI()(.{
            .id = clay.ElementId.ID("TransportRow3"),
            .layout = .{
                .direction = .left_to_right,
                .child_gap = 20,
                .child_alignment = .{ .y = .center },
            },
        })({
            const cb_opts = widgets.CheckboxOpts{
                .box_size = 24 * z,
                .font_size = @intFromFloat(@round(18 * z)),
            };
            _ = widgets.checkbox("Note Labels", &state.show_note_labels, cb_opts);
            _ = widgets.checkbox("Master Staff", &state.show_master_staff, cb_opts);

            if (song_opt.* != null) {
                const sl_fs: u16 = @intFromFloat(@round(16 * z));
                const sl_h: f32 = 24 * z;
                const old_blend = state.balance_blend;
                _ = widgets.sliderFloat("Balance", &state.balance_blend, 0.0, 1.0, &state.balance_slider, .{
                    .width = 160 * z,
                    .height = sl_h,
                    .font_size = sl_fs,
                });
                if (@abs(state.balance_blend - old_blend) > 0.001) {
                    applyBalanceBlend(track_states, state.balance_blend);
                }
            }
        });
    });
}

fn drawSheetMusicArea(
    song: *midi.Song,
    notation_opt: *?music_theory.NotationModel,
    state: *RenderState,
    player: *playback.PlaybackEngine,
    track_states: *[MAX_TRACKS]TrackDisplayState,
    fb_w: f32,
    fb_h: f32,
) void {
    _ = fb_w;
    _ = fb_h;

    const s = state.music_scale;
    const z = state.ui_zoom;
    const sh = score_renderer.base_staff_height * s;
    const mh = score_renderer.base_master_height * s;
    const top_margin = score_renderer.score_top_margin * s;
    const ch = score_renderer.collapsed_track_height * s;

    // Compute total content height (must match renderer's layout exactly)
    var total_content_h: f32 = top_margin;
    if (state.show_master_staff) total_content_h += mh;
    if (notation_opt.*) |*model| {
        for (model.staves) |staff| {
            const ti: usize = @intCast(@min(staff.track_index, MAX_TRACKS - 1));
            if (track_states[ti].expanded) {
                total_content_h += sh;
            } else {
                total_content_h += ch;
            }
        }
    }
    total_content_h += sh; // bottom padding

    clay.UI()(.{
        .id = clay.ElementId.ID("SheetMusic"),
        .layout = .{
            .sizing = .grow,
            .direction = .top_to_bottom,
            .child_gap = 4,
        },
        .background_color = theme.bg_child,
        .corner_radius = .all(theme.radius_child),
        .border = .{ .color = theme.border_default, .width = .outside(1) },
    })({
        // Horizontal scroll bar (stays fixed at top, does not scroll vertically)
        clay.UI()(.{
            .id = clay.ElementId.ID("HScrollRow"),
            .layout = .{
                .sizing = .{ .w = .grow, .h = .fit },
                .padding = .{ .left = 8, .right = 8, .top = 4, .bottom = 4 },
            },
        })({
            const total_content_w = score_renderer.tickToPixelX(song.duration_ticks, song.ticks_per_quarter, 1.0, s) + 100;
            const max_scroll = @max(1.0, total_content_w - 800);
            _ = widgets.sliderFloat("Scroll", &state.scroll_x, 0, max_scroll, &state.hscroll_slider, .{
                .width = 500 * z,
                .height = 20 * z,
                .show_label = false,
            });

            // Auto-scroll during playback
            if (player.state == .playing) {
                const playback_x = score_renderer.tickToPixelX(player.current_tick, song.ticks_per_quarter, 1.0, s);
                state.scroll_x = @max(0, playback_x - 300);
            }
            state.scroll_x = @max(0, @min(state.scroll_x, max_scroll));
        });

        // Single scroll container for both panels — scrolls together
        clay.UI()(.{
            .id = clay.ElementId.ID("ContentArea"),
            .layout = .{
                .sizing = .grow,
                .direction = .left_to_right,
                .child_gap = 0,
            },
            .clip = .{ .vertical = true, .child_offset = clay.getScrollOffset() },
        })({
            const panel_w: f32 = 160 * z; // scales with zoom

            // Left panel: track controls (h=fit so content overflows into scroll)
            clay.UI()(.{
                .id = clay.ElementId.ID("TrackPanel"),
                .layout = .{
                    .sizing = .{ .w = .fixed(panel_w), .h = .fit },
                    .direction = .top_to_bottom,
                    .child_gap = 2,
                },
                .background_color = theme.bg_window,
            })({
                // Top margin matching score's internal top margin
                clay.UI()(.{
                    .id = clay.ElementId.ID("TrackPanelTopSpacer"),
                    .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(top_margin) } },
                })({});

                // Master staff row
                if (state.show_master_staff) {
                    clay.UI()(.{
                        .id = clay.ElementId.ID("MasterTrackRow"),
                        .layout = .{
                            .sizing = .{ .w = .grow, .h = .fixed(mh) },
                            .padding = .{ .left = 8, .top = 4, .right = 8, .bottom = 4 },
                            .child_alignment = .{ .y = .center },
                        },
                        .background_color = theme.bg_child,
                        .border = .{ .color = theme.track_border, .width = .outside(1) },
                        .corner_radius = .all(4),
                    })({
                        clay.text("Master", .{
                            .font_size = @intFromFloat(@round(16 * z)),
                            .color = theme.neon,
                        });
                    });
                }

                // Per-staff rows — grouped by track with expander
                if (notation_opt.*) |*model| {
                    const fs_name: u16 = @intFromFloat(@round(20 * z));
                    const fs_ctrl: u16 = @intFromFloat(@round(17 * z));
                    const fs_clef: u16 = @intFromFloat(@round(18 * z));
                    const fs_vol: u16 = @intFromFloat(@round(16 * z));

                    var prev_track_idx: i32 = -1;
                    for (model.staves, 0..) |staff, si| {
                        const track_idx: usize = @intCast(@min(staff.track_index, MAX_TRACKS - 1));
                        const ts = &track_states[track_idx];
                        const is_first_staff = @as(i32, @intCast(track_idx)) != prev_track_idx;
                        prev_track_idx = @intCast(track_idx);
                        const row_bg = if (track_idx % 2 == 0) theme.track_bg_even else theme.track_bg_odd;

                        if (!ts.expanded) {
                            if (is_first_staff) {
                                const hdr_id = clay.ElementId.IDI("TrackHdr", @intCast(track_idx));
                                const hdr_hovered = clay.pointerOver(hdr_id);

                                const track = if (track_idx < song.tracks.len) &song.tracks[track_idx] else null;
                                var name_buf: [32]u8 = undefined;
                                const name = if (track) |t| (if (t.name.len > 0) t.name else std.fmt.bufPrint(&name_buf, "Track {d}", .{track_idx}) catch "Track") else std.fmt.bufPrint(&name_buf, "Track {d}", .{track_idx}) catch "Track";

                                clay.UI()(.{
                                    .id = hdr_id,
                                    .layout = .{
                                        .sizing = .{ .w = .grow, .h = .fixed(ch) },
                                        .direction = .left_to_right,
                                        .child_gap = 6,
                                        .child_alignment = .{ .y = .center },
                                        .padding = .{ .left = 6, .right = 6, .top = 2, .bottom = 2 },
                                    },
                                    .background_color = if (hdr_hovered) theme.header_hover else row_bg,
                                })({
                                    clay.text(">", .{ .font_size = fs_name, .color = theme.neon });
                                    clay.text(name, .{ .font_size = fs_name, .color = theme.text_disabled });
                                });

                                if (hdr_hovered and widgets.mouseReleased()) {
                                    ts.expanded = true;
                                }
                            }
                            if (!is_first_staff) {
                                clay.UI()(.{
                                    .id = clay.ElementId.IDI("StaffRowC", @intCast(si)),
                                    .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(ch) } },
                                })({});
                            }
                            continue;
                        }

                        // Expanded: track controls (no border here — drawn in score renderer)
                        clay.UI()(.{
                            .id = clay.ElementId.IDI("StaffRow", @intCast(si)),
                            .layout = .{
                                .sizing = .{ .w = .grow, .h = .fixed(sh) },
                                .direction = .top_to_bottom,
                                .padding = .{ .left = 6, .top = 6, .right = 6, .bottom = 6 },
                                .child_gap = 4,
                            },
                            .background_color = row_bg,
                        })({
                            if (is_first_staff) {
                                const hdr_id = clay.ElementId.IDI("TrackHdr", @intCast(track_idx));
                                const hdr_hovered = clay.pointerOver(hdr_id);

                                const track = if (track_idx < song.tracks.len) &song.tracks[track_idx] else null;
                                var name_buf: [32]u8 = undefined;
                                const name = if (track) |t| (if (t.name.len > 0) t.name else std.fmt.bufPrint(&name_buf, "Track {d}", .{track_idx}) catch "Track") else std.fmt.bufPrint(&name_buf, "Track {d}", .{track_idx}) catch "Track";

                                clay.UI()(.{
                                    .id = hdr_id,
                                    .layout = .{
                                        .sizing = .{ .w = .grow, .h = .fit },
                                        .direction = .left_to_right,
                                        .child_gap = 6,
                                        .child_alignment = .{ .y = .center },
                                        .padding = .{ .left = 4, .right = 4, .top = 2, .bottom = 2 },
                                    },
                                    .background_color = if (hdr_hovered) theme.header_hover else theme.header_default,
                                    .corner_radius = .all(4),
                                })({
                                    clay.text("v", .{ .font_size = fs_name, .color = theme.neon });
                                    clay.text(name, .{ .font_size = fs_name, .color = theme.text_primary });
                                });

                                if (hdr_hovered and widgets.mouseReleased()) {
                                    ts.expanded = false;
                                }

                                const tcb = widgets.CheckboxOpts{
                                    .box_size = 22 * z,
                                    .font_size = fs_ctrl,
                                };
                                // Controls stacked vertically to prevent overflow
                                clay.UI()(.{
                                    .id = clay.ElementId.IDI("TrackCtrl", @intCast(track_idx)),
                                    .layout = .{ .direction = .top_to_bottom, .child_gap = 4 },
                                })({
                                    clay.UI()(.{
                                        .id = clay.ElementId.IDI("TrackCtrlCB", @intCast(track_idx)),
                                        .layout = .{ .direction = .left_to_right, .child_gap = 10, .child_alignment = .{ .y = .center } },
                                    })({
                                        _ = widgets.checkbox("Mute", &ts.muted, tcb);
                                        _ = widgets.checkbox("In Master", &ts.include_in_master, tcb);
                                    });

                                    _ = widgets.sliderFloatI("Vol", "Vol", @intCast(track_idx), &ts.volume, 0.0, 3.0, &ts.volume_slider, .{
                                        .width = @max(80, panel_w - 40), .height = 20 * z, .show_label = true,
                                        .font_size = fs_vol,
                                    });
                                });
                            } else {
                                const clef_str: []const u8 = if (staff.clef == .treble) "Treble" else "Bass";
                                clay.text(clef_str, .{ .font_size = fs_clef, .color = theme.text_disabled });
                            }
                        });
                    }
                }

                // Bottom padding
                clay.UI()(.{
                    .id = clay.ElementId.ID("TrackPanelBottom"),
                    .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(sh) } },
                })({});
            }); // end TrackPanel

            // Right panel: score canvas with matching explicit height
            if (notation_opt.*) |*model| {
                score_render_state = .{
                    .scroll_x = state.scroll_x,
                    .zoom = 1.0,
                    .show_note_labels = state.show_note_labels,
                    .show_master_staff = state.show_master_staff,
                };
                score_data = .{
                    .model = model,
                    .song = song,
                    .state = &score_render_state,
                    .player = player,
                    .track_states = track_states,
                    .ui_scale = s,
                    .scroll_y = 0,
                };
                score_data_valid = true;

                clay.UI()(.{
                    .id = clay.ElementId.ID("ScoreCanvas"),
                    .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(total_content_h) } },
                    .custom = .{ .custom_data = @ptrCast(&score_data) },
                })({});
            } else {
                clay.UI()(.{
                    .id = clay.ElementId.ID("ScoreEmpty"),
                    .layout = .{
                        .sizing = .grow,
                        .child_alignment = .{ .x = .center, .y = .center },
                    },
                })({
                    clay.text("Notation model not available", .{
                        .font_size = @intFromFloat(@round(18 * z)),
                        .color = theme.text_disabled,
                    });
                });
            }
        }); // end ContentArea
    }); // end SheetMusic
}

fn drawEmptyState(z: f32) void {
    clay.UI()(.{
        .id = clay.ElementId.ID("EmptyState"),
        .layout = .{
            .sizing = .grow,
            .child_alignment = .{ .x = .center, .y = .center },
            .direction = .top_to_bottom,
            .child_gap = 12,
        },
        .background_color = theme.bg_child,
        .corner_radius = .all(theme.radius_child),
        .border = .{ .color = theme.border_default, .width = .outside(1) },
    })({
        clay.text("No MIDI file loaded.", .{
            .font_size = @intFromFloat(@round(28 * z)),
            .color = theme.text_disabled,
        });
        clay.text("Click \"Open\" to load a MIDI file.", .{
            .font_size = @intFromFloat(@round(20 * z)),
            .color = theme.text_disabled,
        });
    });
}
