const std = @import("std");

const win32 = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
    @cInclude("commdlg.h");
});

const MAX_PATH_LEN = 260;

/// Opens a native Windows file dialog filtered to MIDI files.
/// Returns a heap-allocated UTF-8 path, or null if the user cancelled.
/// Caller must free the returned slice with `allocator.free()`.
pub fn openMidiFile(allocator: std.mem.Allocator, _: ?*anyopaque) ?[]const u8 {
    var filename_buf: [MAX_PATH_LEN]u16 = [_]u16{0} ** MAX_PATH_LEN;

    // Filter string: "MIDI Files (*.mid;*.midi)\0*.mid;*.midi\0All Files (*.*)\0*.*\0\0"
    const filter = toWide("MIDI Files (*.mid;*.midi)\x00*.mid;*.midi\x00All Files (*.*)\x00\x00");
    const title = toWide("Open MIDI File\x00");

    var ofn: win32.OPENFILENAMEW = std.mem.zeroes(win32.OPENFILENAMEW);
    ofn.lStructSize = @sizeOf(win32.OPENFILENAMEW);
    ofn.hwndOwner = null; // HWND from GLFW may not satisfy alignment — dialog works fine without owner
    ofn.lpstrFilter = &filter;
    ofn.lpstrFile = &filename_buf;
    ofn.nMaxFile = MAX_PATH_LEN;
    ofn.lpstrTitle = &title;
    ofn.Flags = win32.OFN_FILEMUSTEXIST | win32.OFN_PATHMUSTEXIST | win32.OFN_NOCHANGEDIR;

    if (win32.GetOpenFileNameW(&ofn) == 0) {
        return null; // User cancelled or error
    }

    // Find the null terminator in the wide string
    var len: usize = 0;
    while (len < MAX_PATH_LEN and filename_buf[len] != 0) : (len += 1) {}

    // Convert UTF-16LE to UTF-8
    const utf8 = std.unicode.utf16LeToUtf8Alloc(allocator, filename_buf[0..len]) catch return null;
    return utf8;
}

fn toWide(comptime s: []const u8) [s.len]u16 {
    var result: [s.len]u16 = undefined;
    for (s, 0..) |byte, i| {
        result[i] = @intCast(byte);
    }
    return result;
}
