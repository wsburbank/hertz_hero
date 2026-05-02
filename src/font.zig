const std = @import("std");
const clay = @import("clay");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;

const stb = @cImport({
    @cInclude("stb_truetype.h");
});

pub const GlyphQuad = struct {
    // Screen coords
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    // Texture (atlas) coords
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
};

pub const Font = struct {
    baked_chars: [96]stb.stbtt_bakedchar, // ASCII 32-127
    atlas_texture: gl.Uint,
    atlas_w: i32,
    atlas_h: i32,
    bake_pixel_height: f32,
    // Font metrics (in bake_pixel_height scale)
    ascent: f32,
    descent: f32,
    line_gap: f32,
};

pub const MAX_FONTS = 4;

pub const FontContext = struct {
    fonts: [MAX_FONTS]?Font = [_]?Font{null} ** MAX_FONTS,

    pub fn init() FontContext {
        return .{};
    }

    pub fn deinit(self: *FontContext) void {
        for (&self.fonts) |*slot| {
            if (slot.*) |f| {
                gl.deleteTextures(1, &f.atlas_texture);
                slot.* = null;
            }
        }
    }

    /// Load a TTF font into a slot. Bakes ASCII 32-127 into a texture atlas.
    pub fn loadFont(self: *FontContext, slot: u16, file_path: []const u8, pixel_height: f32) !void {
        if (slot >= MAX_FONTS) return error.InvalidFontSlot;

        // Read the TTF file
        const file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();
        const file_size = try file.getEndPos();
        const allocator = std.heap.page_allocator;
        const ttf_data = try allocator.alloc(u8, file_size);
        defer allocator.free(ttf_data);
        const bytes_read = try file.readAll(ttf_data);
        if (bytes_read != file_size) return error.IncompleteRead;

        // Bake the font atlas
        const atlas_w: i32 = 1024;
        const atlas_h: i32 = 1024;
        const atlas_pixels = try allocator.alloc(u8, @intCast(@as(u64, @intCast(atlas_w)) * @as(u64, @intCast(atlas_h))));
        defer allocator.free(atlas_pixels);

        var baked_chars: [96]stb.stbtt_bakedchar = undefined;
        const result = stb.stbtt_BakeFontBitmap(
            ttf_data.ptr,
            0, // font offset
            pixel_height,
            atlas_pixels.ptr,
            atlas_w,
            atlas_h,
            32, // first char (space)
            96, // num chars
            &baked_chars,
        );
        if (result <= 0) {
            std.debug.print("stbtt_BakeFontBitmap warning: only fit {d} rows\n", .{result});
        }

        // Get font metrics
        var font_info: stb.stbtt_fontinfo = undefined;
        if (stb.stbtt_InitFont(&font_info, ttf_data.ptr, 0) == 0) {
            return error.FontInitFailed;
        }
        var ascent_i: c_int = 0;
        var descent_i: c_int = 0;
        var line_gap_i: c_int = 0;
        stb.stbtt_GetFontVMetrics(&font_info, &ascent_i, &descent_i, &line_gap_i);
        const scale = stb.stbtt_ScaleForPixelHeight(&font_info, pixel_height);

        // Upload atlas to OpenGL texture
        var tex: gl.Uint = 0;
        gl.genTextures(1, &tex);
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RED,
            atlas_w,
            atlas_h,
            0,
            gl.RED,
            gl.UNSIGNED_BYTE,
            atlas_pixels.ptr,
        );
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.bindTexture(gl.TEXTURE_2D, 0);

        // Clean up old font if present
        if (self.fonts[slot]) |old| {
            gl.deleteTextures(1, &old.atlas_texture);
        }

        self.fonts[slot] = Font{
            .baked_chars = baked_chars,
            .atlas_texture = tex,
            .atlas_w = atlas_w,
            .atlas_h = atlas_h,
            .bake_pixel_height = pixel_height,
            .ascent = @as(f32, @floatFromInt(ascent_i)) * scale,
            .descent = @as(f32, @floatFromInt(descent_i)) * scale,
            .line_gap = @as(f32, @floatFromInt(line_gap_i)) * scale,
        };
    }

    /// Clay text measurement callback. Returns the pixel dimensions of the given text.
    pub fn measureText(text: []const u8, config: *clay.TextElementConfig, self_ptr: *FontContext) clay.Dimensions {
        const font_id: usize = @intCast(config.font_id);
        const font_opt = if (font_id < MAX_FONTS) self_ptr.fonts[font_id] else null;
        const f = font_opt orelse {
            // Fallback: rough estimate
            const fs: f32 = @floatFromInt(config.font_size);
            return .{ .w = fs * 0.5 * @as(f32, @floatFromInt(text.len)), .h = fs };
        };

        const target_size: f32 = @floatFromInt(config.font_size);
        const scale_factor = target_size / f.bake_pixel_height;
        const letter_spacing: f32 = @floatFromInt(config.letter_spacing);

        var width: f32 = 0;
        for (text) |ch| {
            if (ch < 32 or ch > 127) continue;
            const idx: usize = ch - 32;
            width += f.baked_chars[idx].xadvance * scale_factor;
            width += letter_spacing;
        }
        // Remove trailing letter_spacing
        if (text.len > 0) width -= letter_spacing;

        const height = if (config.line_height > 0)
            @as(f32, @floatFromInt(config.line_height))
        else
            target_size;

        return .{ .w = width, .h = height };
    }

    /// Generate glyph quads for rendering text. Returns the number of quads written.
    pub fn getGlyphQuads(
        self: *const FontContext,
        font_id: u16,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        letter_spacing: f32,
        out: []GlyphQuad,
    ) usize {
        const fid: usize = @intCast(font_id);
        const font_opt = if (fid < MAX_FONTS) self.fonts[fid] else null;
        const f = font_opt orelse return 0;

        const scale_factor = font_size / f.bake_pixel_height;
        const atlas_w_f: f32 = @floatFromInt(f.atlas_w);
        const atlas_h_f: f32 = @floatFromInt(f.atlas_h);

        var cursor_x = x;
        var count: usize = 0;

        for (text) |ch| {
            if (ch < 32 or ch > 127) continue;
            if (count >= out.len) break;

            const idx: usize = ch - 32;
            const bc = f.baked_chars[idx];

            const gw = @as(f32, @floatFromInt(bc.x1 - bc.x0)) * scale_factor;
            const gh = @as(f32, @floatFromInt(bc.y1 - bc.y0)) * scale_factor;

            const gx = cursor_x + bc.xoff * scale_factor;
            const gy = y + bc.yoff * scale_factor + f.ascent * scale_factor;

            out[count] = .{
                .x0 = gx,
                .y0 = gy,
                .x1 = gx + gw,
                .y1 = gy + gh,
                .u0 = @as(f32, @floatFromInt(bc.x0)) / atlas_w_f,
                .v0 = @as(f32, @floatFromInt(bc.y0)) / atlas_h_f,
                .u1 = @as(f32, @floatFromInt(bc.x1)) / atlas_w_f,
                .v1 = @as(f32, @floatFromInt(bc.y1)) / atlas_h_f,
            };
            count += 1;

            cursor_x += bc.xadvance * scale_factor + letter_spacing;
        }

        return count;
    }
};
