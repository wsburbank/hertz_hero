const std = @import("std");
const midi = @import("midi.zig");

// ============================================================================
// Pitch Spelling
// ============================================================================

pub const NoteName = enum(u3) { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 };
pub const Accidental = enum { double_flat, flat, natural, sharp, double_sharp };

pub const SpelledNote = struct {
    name: NoteName,
    accidental: Accidental,
    octave: i8,

    pub fn label(self: SpelledNote, buf: []u8) []const u8 {
        const names = [7]u8{ 'C', 'D', 'E', 'F', 'G', 'A', 'B' };
        var i: usize = 0;
        buf[i] = names[@intFromEnum(self.name)];
        i += 1;
        switch (self.accidental) {
            .sharp => {
                buf[i] = '#';
                i += 1;
            },
            .flat => {
                buf[i] = 'b';
                i += 1;
            },
            .double_sharp => {
                buf[i] = 'x';
                i += 1;
            },
            .double_flat => {
                buf[i] = 'b';
                i += 1;
                buf[i] = 'b';
                i += 1;
            },
            .natural => {},
        }
        return buf[0..i];
    }
};

/// Map MIDI pitch (0-127) to a diatonic step from C0
/// Returns { diatonic_step, accidental } where diatonic_step is 0=C, 1=D, ..., 6=B per octave
pub fn spellPitch(pitch_val: u7, key_sharps_flats: i8) SpelledNote {
    const pitch: u8 = @intCast(pitch_val);
    const pc: u8 = pitch % 12; // pitch class 0-11
    const octave: i8 = @as(i8, @intCast(pitch / 12)) - 1;

    // Default spelling table (sharp-preference for black notes)
    // C=0, C#=1, D=2, D#=3, E=4, F=5, F#=6, G=7, G#=8, A=9, A#=10, B=11
    const sharp_names = [12]NoteName{ .C, .C, .D, .D, .E, .F, .F, .G, .G, .A, .A, .B };
    const sharp_accidentals = [12]Accidental{ .natural, .sharp, .natural, .sharp, .natural, .natural, .sharp, .natural, .sharp, .natural, .sharp, .natural };

    const flat_names = [12]NoteName{ .C, .D, .D, .E, .E, .F, .G, .G, .A, .A, .B, .B };
    const flat_accidentals = [12]Accidental{ .natural, .flat, .natural, .flat, .natural, .natural, .flat, .natural, .flat, .natural, .flat, .natural };

    if (key_sharps_flats >= 0) {
        return .{ .name = sharp_names[pc], .accidental = sharp_accidentals[pc], .octave = octave };
    } else {
        return .{ .name = flat_names[pc], .accidental = flat_accidentals[pc], .octave = octave };
    }
}

// ============================================================================
// Musical Position
// ============================================================================

pub const MusicalPosition = struct {
    measure: u32, // 0-indexed
    beat: f64, // beat within measure (0.0 to numerator)
    absolute_seconds: f64,
};

pub fn tickToPosition(
    tick: u32,
    tpq: u16,
    tempo_changes: []const midi.TempoChange,
    time_sigs: []const midi.TimeSignature,
) MusicalPosition {
    // Compute seconds
    var seconds: f64 = 0.0;
    var last_tick: u32 = 0;
    var usec_per_quarter: u32 = 500_000;

    for (tempo_changes) |tc| {
        if (tc.tick >= tick) break;
        const dt = tc.tick - last_tick;
        seconds += @as(f64, @floatFromInt(dt)) * @as(f64, @floatFromInt(usec_per_quarter)) / @as(f64, @floatFromInt(tpq)) / 1_000_000.0;
        last_tick = tc.tick;
        usec_per_quarter = tc.microseconds_per_quarter;
    }
    const remaining = tick - last_tick;
    seconds += @as(f64, @floatFromInt(remaining)) * @as(f64, @floatFromInt(usec_per_quarter)) / @as(f64, @floatFromInt(tpq)) / 1_000_000.0;

    // Compute measure/beat
    var numerator: u8 = 4;
    var denom_power: u8 = 2;
    var measure_start_tick: u32 = 0;
    var measure: u32 = 0;

    // Find active time signature
    for (time_sigs) |ts| {
        if (ts.tick > tick) break;
        if (ts.tick > measure_start_tick) {
            // Count measures from last time sig to this one
            const ticks_per_measure = measureTicks(numerator, denom_power, tpq);
            if (ticks_per_measure > 0) {
                const delta_ticks = ts.tick - measure_start_tick;
                measure += delta_ticks / ticks_per_measure;
                measure_start_tick = ts.tick - (delta_ticks % ticks_per_measure);
            }
        }
        numerator = ts.numerator;
        denom_power = ts.denominator_power;
        measure_start_tick = ts.tick;
    }

    const ticks_per_measure = measureTicks(numerator, denom_power, tpq);
    if (ticks_per_measure > 0 and tick >= measure_start_tick) {
        const delta = tick - measure_start_tick;
        measure += delta / ticks_per_measure;
        const tick_in_measure = delta % ticks_per_measure;
        const ticks_per_beat = beatTicks(denom_power, tpq);
        const beat = if (ticks_per_beat > 0) @as(f64, @floatFromInt(tick_in_measure)) / @as(f64, @floatFromInt(ticks_per_beat)) else 0.0;
        return .{ .measure = measure, .beat = beat, .absolute_seconds = seconds };
    }

    return .{ .measure = measure, .beat = 0.0, .absolute_seconds = seconds };
}

fn measureTicks(numerator: u8, denom_power: u8, tpq: u16) u32 {
    // Ticks per whole note = tpq * 4
    // Ticks per beat = tpq * 4 / denominator
    // Ticks per measure = ticks_per_beat * numerator
    const denom: u32 = @as(u32, 1) << @as(u5, @intCast(denom_power));
    return (@as(u32, tpq) * 4 * @as(u32, numerator)) / denom;
}

fn beatTicks(denom_power: u8, tpq: u16) u32 {
    const denom: u32 = @as(u32, 1) << @as(u5, @intCast(denom_power));
    return (@as(u32, tpq) * 4) / denom;
}

// ============================================================================
// Quantization
// ============================================================================

pub const DurationType = enum {
    whole,
    half,
    quarter,
    eighth,
    sixteenth,
    thirty_second,
};

pub const QuantizedNote = struct {
    pitch: u7,
    velocity: u7,
    channel: u4,
    track_index: u16,
    snapped_tick_on: u32,
    snapped_tick_off: u32,
    duration_type: DurationType,
    is_dotted: bool,
    is_triplet: bool,
    voice: u8, // voice assignment (0-3)
    staff: StaffAssignment,
    spelled: SpelledNote,
};

pub const StaffAssignment = enum { treble, bass };

fn quantizeTickToGrid(tick: u32, tpq: u16) u32 {
    // Snap to the finest grid: 16th note triplet = tpq / 6
    const grid: u32 = @max(1, @as(u32, tpq) / 6);
    const remainder = tick % grid;
    if (remainder <= grid / 2) {
        return tick - remainder;
    } else {
        return tick - remainder + grid;
    }
}

fn classifyDuration(ticks: u32, tpq: u16) struct { dur: DurationType, dotted: bool, triplet: bool } {
    const t: f64 = @floatFromInt(ticks);
    const q: f64 = @floatFromInt(tpq);

    // Standard durations in ticks (for tpq = quarter note ticks)
    const whole = q * 4.0;
    const half = q * 2.0;
    const quarter = q;
    const eighth = q / 2.0;
    const sixteenth = q / 4.0;
    const thirty_second = q / 8.0;

    // Triplet variants
    const quarter_trip = q * 2.0 / 3.0;
    const eighth_trip = q / 3.0;
    const sixteenth_trip = q / 6.0;

    // Dotted variants
    const dotted_half = q * 3.0;
    const dotted_quarter = q * 1.5;
    const dotted_eighth = q * 0.75;

    const candidates = [_]struct { dur: DurationType, dotted: bool, triplet: bool, ticks: f64 }{
        .{ .dur = .whole, .dotted = false, .triplet = false, .ticks = whole },
        .{ .dur = .half, .dotted = true, .triplet = false, .ticks = dotted_half },
        .{ .dur = .half, .dotted = false, .triplet = false, .ticks = half },
        .{ .dur = .quarter, .dotted = true, .triplet = false, .ticks = dotted_quarter },
        .{ .dur = .quarter, .dotted = false, .triplet = true, .ticks = quarter_trip },
        .{ .dur = .quarter, .dotted = false, .triplet = false, .ticks = quarter },
        .{ .dur = .eighth, .dotted = true, .triplet = false, .ticks = dotted_eighth },
        .{ .dur = .eighth, .dotted = false, .triplet = true, .ticks = eighth_trip },
        .{ .dur = .eighth, .dotted = false, .triplet = false, .ticks = eighth },
        .{ .dur = .sixteenth, .dotted = false, .triplet = true, .ticks = sixteenth_trip },
        .{ .dur = .sixteenth, .dotted = false, .triplet = false, .ticks = sixteenth },
        .{ .dur = .thirty_second, .dotted = false, .triplet = false, .ticks = thirty_second },
    };

    var best_idx: usize = 5; // default to quarter
    var best_dist: f64 = 999999.0;
    for (candidates, 0..) |c, i| {
        const dist = @abs(t - c.ticks);
        if (dist < best_dist) {
            best_dist = dist;
            best_idx = i;
        }
    }

    return .{
        .dur = candidates[best_idx].dur,
        .dotted = candidates[best_idx].dotted,
        .triplet = candidates[best_idx].triplet,
    };
}

// ============================================================================
// Voice Separation
// ============================================================================

const MAX_VOICES: u8 = 4;

fn separateVoices(notes: []QuantizedNote) void {
    if (notes.len == 0) return;

    // Sort by tick_on, then pitch descending
    std.sort.insertion(QuantizedNote, notes, {}, struct {
        fn lessThan(_: void, a: QuantizedNote, b: QuantizedNote) bool {
            if (a.snapped_tick_on != b.snapped_tick_on) return a.snapped_tick_on < b.snapped_tick_on;
            return a.pitch > b.pitch; // higher pitch first
        }
    }.lessThan);

    var voice_end_ticks: [MAX_VOICES]u32 = .{ 0, 0, 0, 0 };
    var voice_last_pitch: [MAX_VOICES]u7 = .{ 60, 60, 60, 60 };
    var voices_used: u8 = 0;

    for (notes) |*note| {
        var best_voice: u8 = 0;
        var best_dist: u32 = std.math.maxInt(u32);
        var found = false;

        // Find available voice with closest previous pitch
        var v: u8 = 0;
        while (v < voices_used) : (v += 1) {
            if (voice_end_ticks[v] <= note.snapped_tick_on) {
                const pitch_a: i16 = @intCast(note.pitch);
                const pitch_b: i16 = @intCast(voice_last_pitch[v]);
                const dist: u32 = @intCast(@abs(pitch_a - pitch_b));
                if (dist < best_dist) {
                    best_dist = dist;
                    best_voice = v;
                    found = true;
                }
            }
        }

        if (!found and voices_used < MAX_VOICES) {
            best_voice = voices_used;
            voices_used += 1;
            found = true;
        }

        if (!found) {
            best_voice = 0; // overflow into voice 0
        }

        note.voice = best_voice;
        voice_end_ticks[best_voice] = note.snapped_tick_off;
        voice_last_pitch[best_voice] = note.pitch;
    }
}

// ============================================================================
// Notation Model (combines everything)
// ============================================================================

pub const StaffInfo = struct {
    track_index: u16,
    clef: Clef,
    name: []const u8,
    notes: []QuantizedNote,
};

pub const Clef = enum { treble, bass };

pub const NotationModel = struct {
    staves: []StaffInfo,
    measures: []MeasureInfo,
    key_sharps_flats: i8,
    allocator: std.mem.Allocator,

    pub const MeasureInfo = struct {
        tick_start: u32,
        tick_end: u32,
        numerator: u8,
        denom_power: u8,
    };

    pub fn deinit(self: *NotationModel) void {
        for (self.staves) |staff| {
            self.allocator.free(staff.notes);
        }
        self.allocator.free(self.staves);
        self.allocator.free(self.measures);
    }

    pub fn build(allocator: std.mem.Allocator, song: *midi.Song) !NotationModel {
        // Determine key signature
        var key_sf: i8 = 0;
        if (song.key_signatures.len > 0) {
            key_sf = song.key_signatures[0].sharps_flats;
        }

        // Build measure grid
        var measures: std.ArrayList(MeasureInfo) = .empty;
        var numerator: u8 = 4;
        var denom_power: u8 = 2;
        if (song.time_signatures.len > 0) {
            numerator = song.time_signatures[0].numerator;
            denom_power = song.time_signatures[0].denominator_power;
        }
        const tpq = song.ticks_per_quarter;
        var tick: u32 = 0;
        while (tick < song.duration_ticks) {
            const meas_ticks = measureTicks(numerator, denom_power, tpq);
            if (meas_ticks == 0) break;
            try measures.append(allocator, .{
                .tick_start = tick,
                .tick_end = tick + meas_ticks,
                .numerator = numerator,
                .denom_power = denom_power,
            });
            tick += meas_ticks;

            // Check for time sig change at next measure
            for (song.time_signatures) |ts| {
                if (ts.tick > tick - meas_ticks and ts.tick <= tick) {
                    numerator = ts.numerator;
                    denom_power = ts.denominator_power;
                }
            }
        }

        // Build staves from tracks
        var staves: std.ArrayList(StaffInfo) = .empty;

        for (song.tracks, 0..) |track, ti| {
            if (track.notes.len == 0) continue;

            const track_idx: u16 = @intCast(ti);

            // Determine if grand staff (piano-type): split at middle C
            const is_piano = if (track.program) |p| p <= 7 else false;
            const has_treble = track.max_pitch >= 60;
            const has_bass = track.min_pitch < 60;
            const use_grand_staff = is_piano and has_treble and has_bass;

            if (use_grand_staff) {
                // Split into treble and bass staves
                var treble_notes: std.ArrayList(QuantizedNote) = .empty;
                var bass_notes: std.ArrayList(QuantizedNote) = .empty;

                for (track.notes) |note| {
                    const snapped_on = quantizeTickToGrid(note.tick_on, tpq);
                    const snapped_off = quantizeTickToGrid(note.tick_off, tpq);
                    const dur_ticks = if (snapped_off > snapped_on) snapped_off - snapped_on else @as(u32, tpq);
                    const dur = classifyDuration(dur_ticks, tpq);
                    const staff: StaffAssignment = if (note.pitch >= 60) .treble else .bass;

                    const qnote = QuantizedNote{
                        .pitch = note.pitch,
                        .velocity = note.velocity,
                        .channel = note.channel,
                        .track_index = track_idx,
                        .snapped_tick_on = snapped_on,
                        .snapped_tick_off = snapped_off,
                        .duration_type = dur.dur,
                        .is_dotted = dur.dotted,
                        .is_triplet = dur.triplet,
                        .voice = 0,
                        .staff = staff,
                        .spelled = spellPitch(note.pitch, key_sf),
                    };

                    if (staff == .treble) {
                        try treble_notes.append(allocator, qnote);
                    } else {
                        try bass_notes.append(allocator, qnote);
                    }
                }

                const t_slice = try treble_notes.toOwnedSlice(allocator);
                separateVoices(t_slice);
                try staves.append(allocator, .{
                    .track_index = track_idx,
                    .clef = .treble,
                    .name = track.name,
                    .notes = t_slice,
                });

                const b_slice = try bass_notes.toOwnedSlice(allocator);
                separateVoices(b_slice);
                try staves.append(allocator, .{
                    .track_index = track_idx,
                    .clef = .bass,
                    .name = track.name,
                    .notes = b_slice,
                });
            } else {
                // Single staff
                var qnotes: std.ArrayList(QuantizedNote) = .empty;

                const clef: Clef = if (track.max_pitch < 55) .bass else .treble;
                const staff_assign: StaffAssignment = if (clef == .bass) .bass else .treble;

                for (track.notes) |note| {
                    const snapped_on = quantizeTickToGrid(note.tick_on, tpq);
                    const snapped_off = quantizeTickToGrid(note.tick_off, tpq);
                    const dur_ticks = if (snapped_off > snapped_on) snapped_off - snapped_on else @as(u32, tpq);
                    const dur = classifyDuration(dur_ticks, tpq);

                    try qnotes.append(allocator, .{
                        .pitch = note.pitch,
                        .velocity = note.velocity,
                        .channel = note.channel,
                        .track_index = track_idx,
                        .snapped_tick_on = snapped_on,
                        .snapped_tick_off = snapped_off,
                        .duration_type = dur.dur,
                        .is_dotted = dur.dotted,
                        .is_triplet = dur.triplet,
                        .voice = 0,
                        .staff = staff_assign,
                        .spelled = spellPitch(note.pitch, key_sf),
                    });
                }

                const slice = try qnotes.toOwnedSlice(allocator);
                separateVoices(slice);
                try staves.append(allocator, .{
                    .track_index = track_idx,
                    .clef = clef,
                    .name = track.name,
                    .notes = slice,
                });
            }
        }

        return NotationModel{
            .staves = try staves.toOwnedSlice(allocator),
            .measures = try measures.toOwnedSlice(allocator),
            .key_sharps_flats = key_sf,
            .allocator = allocator,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "spell pitch C4" {
    const note = spellPitch(60, 0);
    try std.testing.expectEqual(NoteName.C, note.name);
    try std.testing.expectEqual(Accidental.natural, note.accidental);
    try std.testing.expectEqual(@as(i8, 4), note.octave);
}

test "spell pitch F# in sharp key" {
    const note = spellPitch(66, 2); // D major (2 sharps)
    try std.testing.expectEqual(NoteName.F, note.name);
    try std.testing.expectEqual(Accidental.sharp, note.accidental);
}

test "spell pitch Bb in flat key" {
    const note = spellPitch(70, -1); // F major (1 flat)
    try std.testing.expectEqual(NoteName.B, note.name);
    try std.testing.expectEqual(Accidental.flat, note.accidental);
}

test "measure ticks 4/4 at 384 tpq" {
    try std.testing.expectEqual(@as(u32, 1536), measureTicks(4, 2, 384));
}

test "measure ticks 3/4 at 384 tpq" {
    try std.testing.expectEqual(@as(u32, 1152), measureTicks(3, 2, 384));
}

test "classify quarter note duration" {
    const result = classifyDuration(384, 384);
    try std.testing.expectEqual(DurationType.quarter, result.dur);
    try std.testing.expect(!result.dotted);
    try std.testing.expect(!result.triplet);
}

test "classify eighth note duration" {
    const result = classifyDuration(192, 384);
    try std.testing.expectEqual(DurationType.eighth, result.dur);
}

test "classify eighth triplet duration" {
    const result = classifyDuration(128, 384);
    try std.testing.expectEqual(DurationType.eighth, result.dur);
    try std.testing.expect(result.triplet);
}
