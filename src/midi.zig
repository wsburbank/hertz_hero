const std = @import("std");

// ============================================================================
// Data Structures
// ============================================================================

pub const Note = struct {
    pitch: u7, // 0-127
    velocity: u7, // 0-127
    channel: u4, // 0-15
    tick_on: u32, // absolute tick of note-on
    tick_off: u32, // absolute tick of note-off
    track_index: u16, // which track this came from
};

pub const TempoChange = struct {
    tick: u32,
    microseconds_per_quarter: u32,

    pub fn bpm(self: TempoChange) f64 {
        return 60_000_000.0 / @as(f64, @floatFromInt(self.microseconds_per_quarter));
    }
};

pub const TimeSignature = struct {
    tick: u32,
    numerator: u8,
    denominator_power: u8,
    clocks_per_click: u8,
    notated_32nd_per_quarter: u8,

    pub fn denominator(self: TimeSignature) u16 {
        return @as(u16, 1) << @as(u4, @intCast(self.denominator_power));
    }
};

pub const KeySignature = struct {
    tick: u32,
    sharps_flats: i8,
    is_minor: bool,
};

pub const Track = struct {
    name: []const u8,
    notes: []Note,
    channel: ?u4,
    program: ?u7,
    min_pitch: u7,
    max_pitch: u7,
    /// Initial channel volume from MIDI CC7 (0-127), null if not present
    initial_volume_cc7: ?u7 = null,
    /// Initial expression from MIDI CC11 (0-127), null if not present
    initial_expression_cc11: ?u7 = null,
    /// RMS velocity across all notes (0.0-127.0), for auto-balance
    rms_velocity: f32 = 0,
};

pub const Song = struct {
    format: u16,
    ticks_per_quarter: u16,
    tracks: []Track,
    tempo_changes: []TempoChange,
    time_signatures: []TimeSignature,
    key_signatures: []KeySignature,
    duration_ticks: u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Song) void {
        for (self.tracks) |track| {
            if (track.name.len > 0) self.allocator.free(track.name);
            self.allocator.free(track.notes);
        }
        self.allocator.free(self.tracks);
        self.allocator.free(self.tempo_changes);
        self.allocator.free(self.time_signatures);
        self.allocator.free(self.key_signatures);
    }

    pub fn defaultTempo(self: Song) f64 {
        if (self.tempo_changes.len > 0) return self.tempo_changes[0].bpm();
        return 120.0;
    }

    pub fn tickToSeconds(self: Song, tick: u32) f64 {
        var seconds: f64 = 0.0;
        var last_tick: u32 = 0;
        var usec_pq: u32 = 500_000;
        for (self.tempo_changes) |tc| {
            if (tc.tick >= tick) break;
            const dt = tc.tick - last_tick;
            seconds += @as(f64, @floatFromInt(dt)) * @as(f64, @floatFromInt(usec_pq)) / @as(f64, @floatFromInt(self.ticks_per_quarter)) / 1_000_000.0;
            last_tick = tc.tick;
            usec_pq = tc.microseconds_per_quarter;
        }
        const rem = tick - last_tick;
        seconds += @as(f64, @floatFromInt(rem)) * @as(f64, @floatFromInt(usec_pq)) / @as(f64, @floatFromInt(self.ticks_per_quarter)) / 1_000_000.0;
        return seconds;
    }

    pub fn totalDurationSeconds(self: Song) f64 {
        return self.tickToSeconds(self.duration_ticks);
    }
};

// ============================================================================
// Parser
// ============================================================================

pub const ParseError = error{
    InvalidHeader,
    InvalidTrackHeader,
    UnexpectedEndOfData,
    InvalidVariableLength,
    InvalidStatusByte,
    OutOfMemory,
};

pub fn readVariableLength(data: []const u8, pos: *usize) ParseError!u32 {
    var result: u32 = 0;
    var bytes_read: u8 = 0;
    while (bytes_read < 4) {
        if (pos.* >= data.len) return ParseError.UnexpectedEndOfData;
        const byte = data[pos.*];
        pos.* += 1;
        result = (result << 7) | @as(u32, byte & 0x7F);
        bytes_read += 1;
        if (byte & 0x80 == 0) return result;
    }
    return ParseError.InvalidVariableLength;
}

fn readU16(data: []const u8, pos: usize) ParseError!u16 {
    if (pos + 2 > data.len) return ParseError.UnexpectedEndOfData;
    return (@as(u16, data[pos]) << 8) | @as(u16, data[pos + 1]);
}

fn readU32(data: []const u8, pos: usize) ParseError!u32 {
    if (pos + 4 > data.len) return ParseError.UnexpectedEndOfData;
    return (@as(u32, data[pos]) << 24) | (@as(u32, data[pos + 1]) << 16) | (@as(u32, data[pos + 2]) << 8) | @as(u32, data[pos + 3]);
}

fn readU24(data: []const u8, pos: usize) ParseError!u32 {
    if (pos + 3 > data.len) return ParseError.UnexpectedEndOfData;
    return (@as(u32, data[pos]) << 16) | (@as(u32, data[pos + 1]) << 8) | @as(u32, data[pos + 2]);
}

const PendingNote = struct {
    pitch: u7,
    velocity: u7,
    channel: u4,
    tick_on: u32,
};

pub fn parse(allocator: std.mem.Allocator, data: []const u8) ParseError!Song {
    if (data.len < 14) return ParseError.InvalidHeader;
    if (!std.mem.eql(u8, data[0..4], "MThd")) return ParseError.InvalidHeader;

    const header_len = try readU32(data, 4);
    _ = header_len;
    const format = try readU16(data, 8);
    const num_tracks = try readU16(data, 10);
    const ticks_per_quarter = try readU16(data, 12);

    var tracks: std.ArrayList(Track) = .empty;
    var tempo_changes: std.ArrayList(TempoChange) = .empty;
    var time_signatures: std.ArrayList(TimeSignature) = .empty;
    var key_signatures: std.ArrayList(KeySignature) = .empty;
    var duration_ticks: u32 = 0;

    var pos: usize = 14;
    var track_idx: u16 = 0;
    while (track_idx < num_tracks) : (track_idx += 1) {
        if (pos + 8 > data.len) return ParseError.InvalidTrackHeader;
        if (!std.mem.eql(u8, data[pos .. pos + 4], "MTrk")) return ParseError.InvalidTrackHeader;
        const track_len = try readU32(data, pos + 4);
        pos += 8;
        const track_end = pos + track_len;
        if (track_end > data.len) return ParseError.UnexpectedEndOfData;

        var notes: std.ArrayList(Note) = .empty;
        var pending: std.ArrayList(PendingNote) = .empty;
        defer pending.deinit(allocator);

        var abs_tick: u32 = 0;
        var last_status: u8 = 0;
        var track_name: []const u8 = "";
        var track_channel: ?u4 = null;
        var track_program: ?u7 = null;
        var min_pitch: u7 = 127;
        var max_pitch: u7 = 0;
        var initial_cc7: ?u7 = null;
        var initial_cc11: ?u7 = null;

        while (pos < track_end) {
            const delta = try readVariableLength(data, &pos);
            abs_tick += delta;
            if (pos >= track_end) break;

            var status = data[pos];
            if (status < 0x80) {
                status = last_status;
            } else {
                pos += 1;
            }
            if (status >= 0x80 and status <= 0xEF) last_status = status;

            const msg_type = status & 0xF0;
            const channel: u4 = @intCast(status & 0x0F);

            switch (msg_type) {
                0x80 => {
                    if (pos + 2 > track_end) break;
                    const pitch: u7 = @intCast(data[pos] & 0x7F);
                    pos += 2;
                    finishNote(allocator, &notes, &pending, pitch, channel, abs_tick, track_idx) catch {};
                },
                0x90 => {
                    if (pos + 2 > track_end) break;
                    const pitch: u7 = @intCast(data[pos] & 0x7F);
                    const velocity: u7 = @intCast(data[pos + 1] & 0x7F);
                    pos += 2;
                    if (velocity == 0) {
                        finishNote(allocator, &notes, &pending, pitch, channel, abs_tick, track_idx) catch {};
                    } else {
                        try pending.append(allocator, .{ .pitch = pitch, .velocity = velocity, .channel = channel, .tick_on = abs_tick });
                        if (pitch < min_pitch) min_pitch = pitch;
                        if (pitch > max_pitch) max_pitch = pitch;
                        if (track_channel == null) track_channel = channel;
                    }
                },
                0xA0, 0xE0 => {
                    if (pos + 2 > track_end) break;
                    pos += 2;
                },
                0xB0 => {
                    // Control Change
                    if (pos + 2 > track_end) break;
                    const cc_num = data[pos];
                    const cc_val: u7 = @intCast(data[pos + 1] & 0x7F);
                    pos += 2;
                    // Capture first CC7 (volume) and CC11 (expression) per track
                    if (cc_num == 7 and initial_cc7 == null) initial_cc7 = cc_val;
                    if (cc_num == 11 and initial_cc11 == null) initial_cc11 = cc_val;
                },
                0xC0, 0xD0 => {
                    if (pos + 1 > track_end) break;
                    if (msg_type == 0xC0) track_program = @intCast(data[pos] & 0x7F);
                    pos += 1;
                },
                0xF0 => {
                    if (status == 0xFF) {
                        if (pos + 1 > track_end) break;
                        const meta_type = data[pos];
                        pos += 1;
                        const meta_len = try readVariableLength(data, &pos);
                        if (pos + meta_len > track_end) break;

                        switch (meta_type) {
                            0x03 => {
                                const name_copy = try allocator.alloc(u8, meta_len);
                                @memcpy(name_copy, data[pos .. pos + meta_len]);
                                track_name = name_copy;
                            },
                            0x2F => {
                                if (abs_tick > duration_ticks) duration_ticks = abs_tick;
                            },
                            0x51 => {
                                if (meta_len >= 3) try tempo_changes.append(allocator, .{ .tick = abs_tick, .microseconds_per_quarter = try readU24(data, pos) });
                            },
                            0x58 => {
                                if (meta_len >= 4) try time_signatures.append(allocator, .{ .tick = abs_tick, .numerator = data[pos], .denominator_power = data[pos + 1], .clocks_per_click = data[pos + 2], .notated_32nd_per_quarter = data[pos + 3] });
                            },
                            0x59 => {
                                if (meta_len >= 2) try key_signatures.append(allocator, .{ .tick = abs_tick, .sharps_flats = @as(i8, @bitCast(data[pos])), .is_minor = data[pos + 1] != 0 });
                            },
                            else => {},
                        }
                        pos += meta_len;
                    } else if (status == 0xF0 or status == 0xF7) {
                        const sysex_len = try readVariableLength(data, &pos);
                        pos += sysex_len;
                    }
                },
                else => {},
            }
        }

        // Close pending notes
        for (pending.items) |p| {
            try notes.append(allocator, .{ .pitch = p.pitch, .velocity = p.velocity, .channel = p.channel, .tick_on = p.tick_on, .tick_off = abs_tick, .track_index = track_idx });
        }

        // Compute RMS velocity for auto-balance
        var rms_vel: f32 = 0;
        if (notes.items.len > 0) {
            var sum_sq: f64 = 0;
            for (notes.items) |n| {
                const v: f64 = @floatFromInt(n.velocity);
                sum_sq += v * v;
            }
            rms_vel = @floatCast(@sqrt(sum_sq / @as(f64, @floatFromInt(notes.items.len))));
        }

        try tracks.append(allocator, .{
            .name = track_name,
            .notes = try notes.toOwnedSlice(allocator),
            .channel = track_channel,
            .program = track_program,
            .min_pitch = min_pitch,
            .max_pitch = max_pitch,
            .initial_volume_cc7 = initial_cc7,
            .initial_expression_cc11 = initial_cc11,
            .rms_velocity = rms_vel,
        });

        pos = track_end;
    }

    return Song{
        .format = format,
        .ticks_per_quarter = ticks_per_quarter,
        .tracks = try tracks.toOwnedSlice(allocator),
        .tempo_changes = try tempo_changes.toOwnedSlice(allocator),
        .time_signatures = try time_signatures.toOwnedSlice(allocator),
        .key_signatures = try key_signatures.toOwnedSlice(allocator),
        .duration_ticks = duration_ticks,
        .allocator = allocator,
    };
}

fn finishNote(allocator: std.mem.Allocator, notes: *std.ArrayList(Note), pending: *std.ArrayList(PendingNote), pitch: u7, channel: u4, tick_off: u32, track_idx: u16) !void {
    var i = pending.items.len;
    while (i > 0) {
        i -= 1;
        const p = pending.items[i];
        if (p.pitch == pitch and p.channel == channel) {
            try notes.append(allocator, .{ .pitch = p.pitch, .velocity = p.velocity, .channel = p.channel, .tick_on = p.tick_on, .tick_off = tick_off, .track_index = track_idx });
            _ = pending.orderedRemove(i);
            return;
        }
    }
}

pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !Song {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(data);
    return parse(allocator, data);
}

// ============================================================================
// Utility
// ============================================================================

pub const note_names = [12][]const u8{ "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };

pub fn pitchName(pitch: u7) []const u8 {
    return note_names[pitch % 12];
}

pub fn pitchOctave(pitch: u7) i8 {
    return @as(i8, @intCast(@as(i16, pitch) / 12)) - 1;
}

// ============================================================================
// Tests
// ============================================================================

test "variable length quantity - single byte" {
    var pos: usize = 0;
    const data = [_]u8{0x60};
    try std.testing.expectEqual(@as(u32, 0x60), try readVariableLength(&data, &pos));
    try std.testing.expectEqual(@as(usize, 1), pos);
}

test "variable length quantity - two bytes" {
    var pos: usize = 0;
    const data = [_]u8{ 0x81, 0x00 };
    try std.testing.expectEqual(@as(u32, 128), try readVariableLength(&data, &pos));
}

test "variable length quantity - 384" {
    var pos: usize = 0;
    const data = [_]u8{ 0x83, 0x00 };
    try std.testing.expectEqual(@as(u32, 384), try readVariableLength(&data, &pos));
}

test "variable length quantity - zero" {
    var pos: usize = 0;
    const data = [_]u8{0x00};
    try std.testing.expectEqual(@as(u32, 0), try readVariableLength(&data, &pos));
}

test "parse M83 MIDI file" {
    const allocator = std.testing.allocator;
    var song = try parseFile(allocator, "Music/M83 _ Midnight City .mid");
    defer song.deinit();

    try std.testing.expectEqual(@as(u16, 1), song.format);
    try std.testing.expectEqual(@as(u16, 384), song.ticks_per_quarter);
    try std.testing.expectEqual(@as(usize, 15), song.tracks.len);
    try std.testing.expectEqualStrings("Electric Piano", song.tracks[0].name);
    try std.testing.expect(song.tempo_changes.len > 0);
    try std.testing.expect(song.time_signatures.len > 0);

    const first_tempo = song.tempo_changes[0];
    try std.testing.expect(first_tempo.bpm() > 100.0 and first_tempo.bpm() < 110.0);

    const first_ts = song.time_signatures[0];
    try std.testing.expectEqual(@as(u8, 4), first_ts.numerator);
    try std.testing.expectEqual(@as(u16, 4), first_ts.denominator());

    var total_notes: usize = 0;
    for (song.tracks) |track| total_notes += track.notes.len;
    try std.testing.expect(total_notes > 100);
}
