const std = @import("std");
const midi = @import("midi.zig");
const music_theory = @import("music_theory.zig");

const c = @cImport({
    @cInclude("miniaudio.h");
    @cInclude("fluidsynth.h");
});

// ============================================================================
// Audio Synthesis
// ============================================================================

const SAMPLE_RATE: u32 = 44100;
const MAX_VOICES: usize = 64;

const SynthVoice = struct {
    active: bool = false,
    pitch: u7 = 0,
    velocity: f32 = 0,
    phase: f64 = 0,
    envelope: f32 = 0,
    release: bool = false,
};

const AudioState = struct {
    // FluidSynth (preferred)
    fs_settings: ?*c.fluid_settings_t = null,
    fs_synth: ?*c.fluid_synth_t = null,
    use_fluidsynth: bool = false,

    // Sine-wave fallback
    voices: [MAX_VOICES]SynthVoice = [_]SynthVoice{.{}} ** MAX_VOICES,

    master_volume: f32 = 0.8,
};

var audio_state: AudioState = .{};

fn midiToFreq(pitch: u7) f64 {
    return 440.0 * std.math.pow(f64, 2.0, (@as(f64, @floatFromInt(pitch)) - 69.0) / 12.0);
}

fn initFluidSynth() void {
    const settings = c.new_fluid_settings() orelse {
        std.debug.print("FluidSynth: failed to create settings\n", .{});
        return;
    };

    // We render audio ourselves via write_float — no FluidSynth audio driver
    _ = c.fluid_settings_setstr(settings, "audio.driver", "none");
    _ = c.fluid_settings_setnum(settings, "synth.sample-rate", @as(f64, @floatFromInt(SAMPLE_RATE)));
    _ = c.fluid_settings_setnum(settings, "synth.gain", 1.0);

    const synth = c.new_fluid_synth(settings) orelse {
        std.debug.print("FluidSynth: failed to create synth\n", .{});
        c.delete_fluid_settings(settings);
        return;
    };

    // Try to load a soundfont
    const sf_id = c.fluid_synth_sfload(synth, "soundfonts/GeneralUser_GS.sf2", 1);
    if (sf_id < 0) {
        std.debug.print("FluidSynth: failed to load soundfont (soundfonts/GeneralUser_GS.sf2) — falling back to sine synth\n", .{});
        c.delete_fluid_synth(synth);
        c.delete_fluid_settings(settings);
        return;
    }

    audio_state.fs_settings = settings;
    audio_state.fs_synth = synth;
    audio_state.use_fluidsynth = true;
    std.debug.print("FluidSynth: initialized successfully (sfont id={})\n", .{sf_id});
}

fn audioCallback(
    device_ptr: [*c]c.ma_device,
    output_ptr: ?*anyopaque,
    input_ptr: ?*const anyopaque,
    frame_count: c.ma_uint32,
) callconv(.c) void {
    _ = device_ptr;
    _ = input_ptr;

    const output: [*]f32 = @ptrCast(@alignCast(output_ptr orelse return));
    const frames: usize = @intCast(frame_count);
    const state = &audio_state;

    if (state.use_fluidsynth) {
        if (state.fs_synth) |synth| {
            // FluidSynth renders interleaved stereo f32 directly
            // lout = output, loff = 0, lincr = 2 (left samples at even indices)
            // rout = output, roff = 1, rincr = 2 (right samples at odd indices)
            _ = c.fluid_synth_write_float(
                synth,
                @intCast(frames),
                output,
                0,
                2,
                output,
                1,
                2,
            );
            // Apply master volume
            const total_samples = frames * 2;
            for (0..total_samples) |i| {
                output[i] *= state.master_volume;
            }
        }
        return;
    }

    // Sine-wave fallback
    for (0..frames) |i| {
        var sample: f32 = 0;

        for (&state.voices) |*voice| {
            if (!voice.active) continue;

            const freq = midiToFreq(voice.pitch);
            const phase_inc = freq / @as(f64, @floatFromInt(SAMPLE_RATE));

            // Simple sine wave with soft attack/release envelope
            const sine: f32 = @floatCast(@sin(voice.phase * std.math.pi * 2.0));

            // Envelope
            if (voice.release) {
                voice.envelope -= 0.002;
                if (voice.envelope <= 0) {
                    voice.active = false;
                    voice.envelope = 0;
                    continue;
                }
            } else if (voice.envelope < 1.0) {
                voice.envelope += 0.01; // attack
                if (voice.envelope > 1.0) voice.envelope = 1.0;
            }

            sample += sine * voice.velocity * voice.envelope;
            voice.phase += phase_inc;
            if (voice.phase >= 1.0) voice.phase -= 1.0;
        }

        // Stereo output
        const out = sample * state.master_volume;
        output[i * 2] = out;
        output[i * 2 + 1] = out;
    }
}

// ============================================================================
// Playback Engine
// ============================================================================

pub const PlaybackState = enum { stopped, playing, paused };

pub const PlaybackEngine = struct {
    state: PlaybackState = .stopped,
    current_tick: u32 = 0,
    tempo_bpm: f32 = 120.0,
    tick_accumulator: f64 = 0,
    track_muted: [16]bool = [_]bool{false} ** 16,
    track_volumes: [16]f32 = [_]f32{1.0} ** 16,
    song: ?*midi.Song = null,
    device: c.ma_device = undefined,
    device_initialized: bool = false,

    pub fn init() PlaybackEngine {
        return PlaybackEngine{};
    }

    /// Must be called after the PlaybackEngine is at its final memory location.
    /// ma_device stores internal self-pointers, so it cannot be initialized before a move.
    pub fn initAudio(self: *PlaybackEngine) void {
        // Try FluidSynth first
        initFluidSynth();

        var config = c.ma_device_config_init(c.ma_device_type_playback);
        config.playback.format = c.ma_format_f32;
        config.playback.channels = 2;
        config.sampleRate = SAMPLE_RATE;
        config.dataCallback = &audioCallback;

        if (c.ma_device_init(null, &config, &self.device) == c.MA_SUCCESS) {
            self.device_initialized = true;
            _ = c.ma_device_start(&self.device);
        } else {
            std.debug.print("Failed to initialize audio device\n", .{});
        }
    }

    pub fn deinit(self: *PlaybackEngine) void {
        if (self.device_initialized) {
            c.ma_device_uninit(&self.device);
        }
        // Clean up FluidSynth
        if (audio_state.fs_synth) |synth| {
            c.delete_fluid_synth(synth);
            audio_state.fs_synth = null;
        }
        if (audio_state.fs_settings) |settings| {
            c.delete_fluid_settings(settings);
            audio_state.fs_settings = null;
        }
        audio_state.use_fluidsynth = false;
    }

    pub fn load(self: *PlaybackEngine, song: *midi.Song) void {
        self.song = song;
        self.tempo_bpm = @floatCast(song.defaultTempo());
        self.current_tick = 0;
        self.state = .stopped;

        // Set up FluidSynth program changes per track
        if (audio_state.use_fluidsynth) {
            if (audio_state.fs_synth) |synth| {
                for (song.tracks) |track| {
                    if (track.channel) |ch| {
                        if (track.program) |prog| {
                            _ = c.fluid_synth_program_change(synth, @as(c_int, ch), @as(c_int, prog));
                        }
                    }
                }
            }
        }
    }

    pub fn setProgramChange(channel: u4, program: u7) void {
        if (audio_state.use_fluidsynth) {
            if (audio_state.fs_synth) |synth| {
                _ = c.fluid_synth_program_change(synth, @as(c_int, channel), @as(c_int, program));
                std.debug.print("FluidSynth: program change ch={} prog={}\n", .{ channel, program });
            }
        }
    }

    /// Set real-time channel volume via MIDI CC7.
    /// Slider 0.0-3.0 mapped so that 1.0 = CC7 100 (GM default), 0.0 = 0, 3.0 = 127.
    pub fn setChannelVolume(channel: u4, volume: f32) void {
        if (audio_state.use_fluidsynth) {
            if (audio_state.fs_synth) |synth| {
                const cc_val: c_int = @intFromFloat(@min(127.0, @max(0.0, volume * 100.0)));
                _ = c.fluid_synth_cc(synth, @as(c_int, channel), 7, cc_val);
            }
        }
    }

    /// Set real-time channel expression via MIDI CC11.
    /// Affects currently sounding notes. Slider 1.0 = CC11 85 (normal),
    /// 1.5 = CC11 127 (max boost), 0.0 = silent.
    pub fn setChannelExpression(channel: u4, expression: f32) void {
        if (audio_state.use_fluidsynth) {
            if (audio_state.fs_synth) |synth| {
                const cc_val: c_int = @intFromFloat(@min(127.0, @max(0.0, expression * 85.0)));
                _ = c.fluid_synth_cc(synth, @as(c_int, channel), 11, cc_val);
            }
        }
    }

    pub fn play(self: *PlaybackEngine) void {
        self.state = .playing;
    }

    pub fn pause(self: *PlaybackEngine) void {
        self.state = .paused;
        if (audio_state.use_fluidsynth) {
            if (audio_state.fs_synth) |synth| {
                var ch: c_int = 0;
                while (ch < 16) : (ch += 1) {
                    _ = c.fluid_synth_all_notes_off(synth, ch);
                }
            }
        } else {
            for (&audio_state.voices) |*voice| {
                if (voice.active) voice.release = true;
            }
        }
    }

    pub fn stop(self: *PlaybackEngine) void {
        self.state = .stopped;
        self.current_tick = 0;
        self.tick_accumulator = 0;
        if (audio_state.use_fluidsynth) {
            if (audio_state.fs_synth) |synth| {
                var ch: c_int = 0;
                while (ch < 16) : (ch += 1) {
                    _ = c.fluid_synth_all_notes_off(synth, ch);
                }
            }
        } else {
            for (&audio_state.voices) |*voice| {
                voice.active = false;
            }
        }
    }

    pub fn update(self: *PlaybackEngine, delta_seconds: f64, song: *midi.Song) void {
        if (self.state != .playing) return;

        // Compute ticks elapsed this frame
        const ticks_per_second = @as(f64, @floatFromInt(song.ticks_per_quarter)) * @as(f64, self.tempo_bpm) / 60.0;
        self.tick_accumulator += delta_seconds * ticks_per_second;

        const ticks_elapsed: u32 = @intFromFloat(@floor(self.tick_accumulator));
        self.tick_accumulator -= @as(f64, @floatFromInt(ticks_elapsed));

        if (ticks_elapsed == 0) return;

        const old_tick = self.current_tick;
        const new_tick = old_tick + ticks_elapsed;

        // Fire note events
        for (song.tracks, 0..) |track, ti| {
            const idx: u4 = @intCast(@min(ti, 15));
            if (self.track_muted[idx]) continue;

            const vol = self.track_volumes[idx];

            for (track.notes) |note| {
                // Note-on events in range
                if (note.tick_on >= old_tick and note.tick_on < new_tick) {
                    synthNoteOn(note.pitch, note.velocity, vol, note.channel);
                }
                // Note-off events in range
                if (note.tick_off >= old_tick and note.tick_off < new_tick) {
                    synthNoteOff(note.pitch, note.channel);
                }
            }
        }

        self.current_tick = new_tick;

        // Stop at end of song
        if (self.current_tick >= song.duration_ticks) {
            self.stop();
        }
    }

    pub fn getMusicalPosition(self: *const PlaybackEngine, song: *midi.Song) music_theory.MusicalPosition {
        return music_theory.tickToPosition(
            self.current_tick,
            song.ticks_per_quarter,
            song.tempo_changes,
            song.time_signatures,
        );
    }
};

fn synthNoteOn(pitch: u7, velocity: u7, track_vol: f32, channel: u4) void {
    if (audio_state.use_fluidsynth) {
        if (audio_state.fs_synth) |synth| {
            // track_vol = per-track slider (velocity scaling, default 1.0)
            // CC7 is set separately from base_volume (balance blend) — no double-application
            const vel_scaled: c_int = @intFromFloat(@as(f32, @floatFromInt(velocity)) * track_vol);
            const vel_clamped: c_int = @min(127, @max(1, vel_scaled));
            _ = c.fluid_synth_noteon(synth, @as(c_int, channel), @as(c_int, pitch), vel_clamped);
        }
        return;
    }

    // Sine-wave fallback (ignores channel)
    const vel_f: f32 = @as(f32, @floatFromInt(velocity)) / 127.0 * track_vol;

    // Check if already playing this pitch — reuse that slot
    for (&audio_state.voices) |*voice| {
        if (voice.active and voice.pitch == pitch and !voice.release) {
            voice.velocity = vel_f;
            voice.envelope = 0.5; // retrigger
            voice.release = false;
            return;
        }
    }

    // Find free voice slot
    for (&audio_state.voices) |*voice| {
        if (!voice.active) {
            voice.* = .{
                .active = true,
                .pitch = pitch,
                .velocity = vel_f,
                .phase = 0,
                .envelope = 0,
                .release = false,
            };
            return;
        }
    }

    // Voice stealing: replace quietest voice
    var quietest: usize = 0;
    var quietest_vol: f32 = 999;
    for (&audio_state.voices, 0..) |*voice, i| {
        const v = voice.velocity * voice.envelope;
        if (v < quietest_vol) {
            quietest_vol = v;
            quietest = i;
        }
    }
    audio_state.voices[quietest] = .{
        .active = true,
        .pitch = pitch,
        .velocity = vel_f,
        .phase = 0,
        .envelope = 0,
        .release = false,
    };
}

fn synthNoteOff(pitch: u7, channel: u4) void {
    if (audio_state.use_fluidsynth) {
        if (audio_state.fs_synth) |synth| {
            _ = c.fluid_synth_noteoff(synth, @as(c_int, channel), @as(c_int, pitch));
        }
        return;
    }

    // Sine-wave fallback (ignores channel)
    for (&audio_state.voices) |*voice| {
        if (voice.active and voice.pitch == pitch and !voice.release) {
            voice.release = true;
            return;
        }
    }
}
