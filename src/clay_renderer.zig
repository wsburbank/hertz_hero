const std = @import("std");
const clay = @import("clay");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const font_mod = @import("font.zig");

// ============================================================================
// Shader sources (OpenGL 3.3 core, adapted from Clay GLES3 reference renderer)
// ============================================================================

const quad_vert_src: [*:0]const u8 =
    \\#version 330 core
    \\layout(location = 0) in vec2 aPos;
    \\layout(location = 1) in vec4 aRect;
    \\layout(location = 2) in vec4 aColor;
    \\layout(location = 3) in vec4 aUV;
    \\layout(location = 4) in vec4 aCornerRadii;
    \\layout(location = 5) in vec4 aBorderWidths;
    \\layout(location = 6) in float aTexSlot;
    \\uniform vec2 uScreen;
    \\out vec2 vPos;
    \\out vec4 vRect;
    \\out vec4 vColor;
    \\out vec2 vUV;
    \\out vec4 vCornerRadii;
    \\out vec4 vBorderWidths;
    \\flat out float vTexSlot;
    \\void main() {
    \\    vec2 pos = vec2(aPos.x * aRect.z + aRect.x, aPos.y * aRect.w + aRect.y);
    \\    vec2 ndc = pos / uScreen * 2.0 - 1.0;
    \\    ndc.y = -ndc.y;
    \\    gl_Position = vec4(ndc, 0.0, 1.0);
    \\    vPos = aPos;
    \\    vRect = aRect;
    \\    vColor = aColor;
    \\    vUV = mix(aUV.xy, aUV.zw, aPos);
    \\    vCornerRadii = aCornerRadii;
    \\    vBorderWidths = aBorderWidths;
    \\    vTexSlot = aTexSlot;
    \\}
    \\
;

const quad_frag_src: [*:0]const u8 =
    \\#version 330 core
    \\in vec2 vPos;
    \\in vec4 vRect;
    \\in vec4 vColor;
    \\in vec2 vUV;
    \\in vec4 vCornerRadii;
    \\in vec4 vBorderWidths;
    \\flat in float vTexSlot;
    \\out vec4 fragColor;
    \\
    \\float roundedRectSDF(vec2 p, vec2 half_size, float r) {
    \\    vec2 d = abs(p) - half_size + vec2(r);
    \\    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
    \\}
    \\
    \\void main() {
    \\    vec2 pixel = vPos * vRect.zw;
    \\    vec2 half_size = vRect.zw * 0.5;
    \\    vec2 center = half_size;
    \\
    \\    // Pick corner radius based on quadrant
    \\    float r = vCornerRadii.x; // TL
    \\    if (pixel.x > half_size.x && pixel.y <= half_size.y) r = vCornerRadii.y; // TR
    \\    if (pixel.x <= half_size.x && pixel.y > half_size.y) r = vCornerRadii.z; // BL
    \\    if (pixel.x > half_size.x && pixel.y > half_size.y) r = vCornerRadii.w; // BR
    \\
    \\    float dist = roundedRectSDF(pixel - center, half_size, r);
    \\    float outerAlpha = 1.0 - smoothstep(-0.5, 0.5, dist);
    \\
    \\    // Border: check if inside inner rect
    \\    vec4 bw = vBorderWidths;
    \\    bool has_border = (bw.x + bw.y + bw.z + bw.w) > 0.0;
    \\    float innerAlpha = 0.0;
    \\    if (has_border) {
    \\        vec2 inner_half = half_size - vec2((bw.x + bw.y) * 0.5, (bw.z + bw.w) * 0.5);
    \\        float inner_r = max(r - max(bw.x, max(bw.y, max(bw.z, bw.w))), 0.0);
    \\        float inner_dist = roundedRectSDF(pixel - center, inner_half, inner_r);
    \\        innerAlpha = 1.0 - smoothstep(-0.5, 0.5, inner_dist);
    \\    }
    \\
    \\    float alpha = has_border ? (outerAlpha - innerAlpha) : outerAlpha;
    \\    if (alpha < 0.001) discard;
    \\
    \\    fragColor = vec4(vColor.rgb, vColor.a * alpha);
    \\}
    \\
;

const text_vert_src: [*:0]const u8 =
    \\#version 330 core
    \\layout(location = 0) in vec2 aPos;
    \\layout(location = 1) in vec2 aUV;
    \\layout(location = 2) in vec4 aColor;
    \\uniform vec2 uScreen;
    \\out vec2 vUV;
    \\out vec4 vColor;
    \\void main() {
    \\    vec2 ndc = aPos / uScreen * 2.0 - 1.0;
    \\    ndc.y = -ndc.y;
    \\    gl_Position = vec4(ndc, 0.0, 1.0);
    \\    vUV = aUV;
    \\    vColor = aColor;
    \\}
    \\
;

const text_frag_src: [*:0]const u8 =
    \\#version 330 core
    \\in vec2 vUV;
    \\in vec4 vColor;
    \\uniform sampler2D uFontAtlas;
    \\out vec4 fragColor;
    \\void main() {
    \\    float coverage = texture(uFontAtlas, vUV).r;
    \\    fragColor = vec4(vColor.rgb, vColor.a * coverage);
    \\}
    \\
;

// ============================================================================
// Instance data structures
// ============================================================================

const RectInstance = extern struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
    radius_tl: f32,
    radius_tr: f32,
    radius_bl: f32,
    radius_br: f32,
    border_l: f32,
    border_r: f32,
    border_t: f32,
    border_b: f32,
    tex_slot: f32,
    _pad: [3]f32 = .{ 0, 0, 0 },
};

const TextVertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const MAX_RECTS = 4096;
const MAX_TEXT_VERTS = 65536;

// ============================================================================
// Custom draw callback for sheet music rendering (Phase 4)
// ============================================================================

pub const CustomDrawFn = *const fn (
    bounding_box: clay.BoundingBox,
    custom_data: ?*anyopaque,
    user_data: ?*anyopaque,
) void;

// ============================================================================
// Renderer
// ============================================================================

pub const ClayRenderer = struct {
    // Quad rendering
    quad_vao: gl.Uint = 0,
    quad_vbo: gl.Uint = 0,
    quad_instance_vbo: gl.Uint = 0,
    quad_shader: gl.Uint = 0,
    quad_screen_loc: gl.Int = 0,
    rect_instances: [MAX_RECTS]RectInstance = undefined,
    rect_count: usize = 0,

    // Text rendering
    text_vao: gl.Uint = 0,
    text_vbo: gl.Uint = 0,
    text_shader: gl.Uint = 0,
    text_screen_loc: gl.Int = 0,
    text_atlas_loc: gl.Int = 0,
    text_vertices: [MAX_TEXT_VERTS]TextVertex = undefined,
    text_vert_count: usize = 0,

    screen_width: f32 = 1920,
    screen_height: f32 = 1080,
    font_ctx: *font_mod.FontContext,

    // Custom draw callback for Phase 4
    custom_draw_fn: ?CustomDrawFn = null,
    custom_draw_user_data: ?*anyopaque = null,

    pub fn init(font_ctx: *font_mod.FontContext) ClayRenderer {
        var self = ClayRenderer{ .font_ctx = font_ctx };
        self.initQuadPipeline();
        self.initTextPipeline();
        return self;
    }

    pub fn deinit(self: *ClayRenderer) void {
        gl.deleteVertexArrays(1, &self.quad_vao);
        gl.deleteBuffers(1, &self.quad_vbo);
        gl.deleteBuffers(1, &self.quad_instance_vbo);
        gl.deleteProgram(self.quad_shader);
        gl.deleteVertexArrays(1, &self.text_vao);
        gl.deleteBuffers(1, &self.text_vbo);
        gl.deleteProgram(self.text_shader);
    }

    fn initQuadPipeline(self: *ClayRenderer) void {
        // Unit quad vertices
        const quad_verts = [_]f32{
            0, 0, 1, 0, 1, 1,
            0, 0, 1, 1, 0, 1,
        };

        // Create VAO
        gl.genVertexArrays(1, &self.quad_vao);
        gl.bindVertexArray(self.quad_vao);

        // Quad VBO (static)
        gl.genBuffers(1, &self.quad_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.quad_vbo);
        gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(quad_verts)), &quad_verts, gl.STATIC_DRAW);
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * @sizeOf(f32), null);

        // Instance VBO (dynamic)
        gl.genBuffers(1, &self.quad_instance_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.quad_instance_vbo);
        gl.bufferData(gl.ARRAY_BUFFER, MAX_RECTS * @sizeOf(RectInstance), null, gl.DYNAMIC_DRAW);

        const stride: gl.Sizei = @sizeOf(RectInstance);
        // location 1: aRect (x,y,w,h)
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(1, 4, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(0));
        gl.vertexAttribDivisor(1, 1);
        // location 3: aUV (u0,v0,u1,v1)
        gl.enableVertexAttribArray(3);
        gl.vertexAttribPointer(3, 4, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(4 * @sizeOf(f32)));
        gl.vertexAttribDivisor(3, 1);
        // location 2: aColor (r,g,b,a)
        gl.enableVertexAttribArray(2);
        gl.vertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(8 * @sizeOf(f32)));
        gl.vertexAttribDivisor(2, 1);
        // location 4: aCornerRadii (tl,tr,bl,br)
        gl.enableVertexAttribArray(4);
        gl.vertexAttribPointer(4, 4, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(12 * @sizeOf(f32)));
        gl.vertexAttribDivisor(4, 1);
        // location 5: aBorderWidths (l,r,t,b)
        gl.enableVertexAttribArray(5);
        gl.vertexAttribPointer(5, 4, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(16 * @sizeOf(f32)));
        gl.vertexAttribDivisor(5, 1);
        // location 6: aTexSlot
        gl.enableVertexAttribArray(6);
        gl.vertexAttribPointer(6, 1, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(20 * @sizeOf(f32)));
        gl.vertexAttribDivisor(6, 1);

        gl.bindVertexArray(0);

        // Compile shader
        self.quad_shader = compileProgram(quad_vert_src, quad_frag_src);
        self.quad_screen_loc = gl.getUniformLocation(self.quad_shader, "uScreen");
    }

    fn initTextPipeline(self: *ClayRenderer) void {
        gl.genVertexArrays(1, &self.text_vao);
        gl.bindVertexArray(self.text_vao);

        gl.genBuffers(1, &self.text_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.text_vbo);
        gl.bufferData(gl.ARRAY_BUFFER, MAX_TEXT_VERTS * @sizeOf(TextVertex), null, gl.DYNAMIC_DRAW);

        const stride: gl.Sizei = @sizeOf(TextVertex);
        // location 0: aPos
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(0));
        // location 1: aUV
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(2 * @sizeOf(f32)));
        // location 2: aColor
        gl.enableVertexAttribArray(2);
        gl.vertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(4 * @sizeOf(f32)));

        gl.bindVertexArray(0);

        self.text_shader = compileProgram(text_vert_src, text_frag_src);
        self.text_screen_loc = gl.getUniformLocation(self.text_shader, "uScreen");
        self.text_atlas_loc = gl.getUniformLocation(self.text_shader, "uFontAtlas");
    }

    /// Render all Clay render commands for this frame.
    pub fn render(self: *ClayRenderer, commands: []clay.RenderCommand) void {
        self.rect_count = 0;
        self.text_vert_count = 0;

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        for (commands) |cmd| {
            switch (cmd.command_type) {
                .rectangle => {
                    const data = cmd.render_data.rectangle;
                    self.pushRect(cmd.bounding_box, data.background_color, data.corner_radius, .{}, -1);
                },
                .border => {
                    const data = cmd.render_data.border;
                    const bw = data.width;
                    self.pushRect(
                        cmd.bounding_box,
                        data.color,
                        data.corner_radius,
                        .{
                            .l = @floatFromInt(bw.left),
                            .r = @floatFromInt(bw.right),
                            .t = @floatFromInt(bw.top),
                            .b = @floatFromInt(bw.bottom),
                        },
                        -1,
                    );
                },
                .text => {
                    const data = cmd.render_data.text;
                    self.pushText(cmd.bounding_box, data);
                },
                .scissor_start => {
                    self.flush();
                    const bb = cmd.bounding_box;
                    const y_gl: gl.Int = @intFromFloat(self.screen_height - (bb.y + bb.height));
                    gl.enable(gl.SCISSOR_TEST);
                    gl.scissor(
                        @intFromFloat(bb.x),
                        y_gl,
                        @intFromFloat(@max(0, bb.width)),
                        @intFromFloat(@max(0, bb.height)),
                    );
                },
                .scissor_end => {
                    self.flush();
                    gl.disable(gl.SCISSOR_TEST);
                },
                .custom => {
                    self.flush();
                    if (self.custom_draw_fn) |draw_fn| {
                        const data = cmd.render_data.custom;
                        draw_fn(cmd.bounding_box, data.custom_data, self.custom_draw_user_data);
                    }
                },
                .image => {
                    // TODO: image rendering (not needed for current feature set)
                    const data = cmd.render_data.image;
                    self.pushRect(cmd.bounding_box, data.background_color, data.corner_radius, .{}, -1);
                },
                .none => {},
            }
        }

        self.flush();
        gl.disable(gl.BLEND);
        gl.disable(gl.SCISSOR_TEST);
    }

    const BorderWidths = struct {
        l: f32 = 0,
        r: f32 = 0,
        t: f32 = 0,
        b: f32 = 0,
    };

    fn pushRect(
        self: *ClayRenderer,
        bb: clay.BoundingBox,
        color: clay.Color,
        cr: clay.CornerRadius,
        bw: BorderWidths,
        tex_slot: f32,
    ) void {
        if (self.rect_count >= MAX_RECTS) {
            self.flushRects();
        }
        self.rect_instances[self.rect_count] = .{
            .x = bb.x,
            .y = bb.y,
            .w = bb.width,
            .h = bb.height,
            .u0 = 0,
            .v0 = 0,
            .u1 = 1,
            .v1 = 1,
            .r = color[0] / 255.0,
            .g = color[1] / 255.0,
            .b = color[2] / 255.0,
            .a = color[3] / 255.0,
            .radius_tl = cr.top_left,
            .radius_tr = cr.top_right,
            .radius_bl = cr.bottom_left,
            .radius_br = cr.bottom_right,
            .border_l = bw.l,
            .border_r = bw.r,
            .border_t = bw.t,
            .border_b = bw.b,
            .tex_slot = tex_slot,
        };
        self.rect_count += 1;
    }

    fn pushText(self: *ClayRenderer, bb: clay.BoundingBox, data: clay.TextRenderData) void {
        const str = data.string_contents.chars[0..@intCast(data.string_contents.length)];
        const font_size: f32 = @floatFromInt(data.font_size);
        const letter_spacing: f32 = @floatFromInt(data.letter_spacing);

        const cr = data.text_color[0] / 255.0;
        const cg = data.text_color[1] / 255.0;
        const cb = data.text_color[2] / 255.0;
        const ca = data.text_color[3] / 255.0;

        var quads: [256]font_mod.GlyphQuad = undefined;
        const count = self.font_ctx.getGlyphQuads(
            data.font_id,
            str,
            bb.x,
            bb.y,
            font_size,
            letter_spacing,
            &quads,
        );

        for (quads[0..count]) |q| {
            if (self.text_vert_count + 6 > MAX_TEXT_VERTS) {
                self.flushText();
            }
            // Two triangles per quad
            const verts = [6]TextVertex{
                .{ .x = q.x0, .y = q.y0, .u = q.u0, .v = q.v0, .r = cr, .g = cg, .b = cb, .a = ca },
                .{ .x = q.x1, .y = q.y0, .u = q.u1, .v = q.v0, .r = cr, .g = cg, .b = cb, .a = ca },
                .{ .x = q.x1, .y = q.y1, .u = q.u1, .v = q.v1, .r = cr, .g = cg, .b = cb, .a = ca },
                .{ .x = q.x0, .y = q.y0, .u = q.u0, .v = q.v0, .r = cr, .g = cg, .b = cb, .a = ca },
                .{ .x = q.x1, .y = q.y1, .u = q.u1, .v = q.v1, .r = cr, .g = cg, .b = cb, .a = ca },
                .{ .x = q.x0, .y = q.y1, .u = q.u0, .v = q.v1, .r = cr, .g = cg, .b = cb, .a = ca },
            };
            @memcpy(self.text_vertices[self.text_vert_count..][0..6], &verts);
            self.text_vert_count += 6;
        }
    }

    fn flush(self: *ClayRenderer) void {
        self.flushRects();
        self.flushText();
    }

    fn flushRects(self: *ClayRenderer) void {
        if (self.rect_count == 0) return;

        gl.useProgram(self.quad_shader);
        gl.uniform2f(self.quad_screen_loc, self.screen_width, self.screen_height);

        gl.bindVertexArray(self.quad_vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.quad_instance_vbo);
        gl.bufferSubData(
            gl.ARRAY_BUFFER,
            0,
            @intCast(self.rect_count * @sizeOf(RectInstance)),
            @ptrCast(&self.rect_instances),
        );

        gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, @intCast(self.rect_count));
        gl.bindVertexArray(0);

        self.rect_count = 0;
    }

    fn flushText(self: *ClayRenderer) void {
        if (self.text_vert_count == 0) return;

        // Bind font atlas from slot 0 (primary font)
        const font_opt = self.font_ctx.fonts[0];
        if (font_opt) |f| {
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, f.atlas_texture);
        } else return;

        gl.useProgram(self.text_shader);
        gl.uniform2f(self.text_screen_loc, self.screen_width, self.screen_height);
        gl.uniform1i(self.text_atlas_loc, 0);

        gl.bindVertexArray(self.text_vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.text_vbo);
        gl.bufferSubData(
            gl.ARRAY_BUFFER,
            0,
            @intCast(self.text_vert_count * @sizeOf(TextVertex)),
            @ptrCast(&self.text_vertices),
        );

        gl.drawArrays(gl.TRIANGLES, 0, @intCast(self.text_vert_count));
        gl.bindVertexArray(0);
        gl.bindTexture(gl.TEXTURE_2D, 0);

        self.text_vert_count = 0;
    }
};

// ============================================================================
// Shader compilation helpers
// ============================================================================

fn compileShader(source: [*:0]const u8, shader_type: gl.Enum) gl.Uint {
    const shader = gl.createShader(shader_type);
    gl.shaderSource(shader, 1, &source, null);
    gl.compileShader(shader);

    var success: gl.Int = 0;
    gl.getShaderiv(shader, gl.COMPILE_STATUS, &success);
    if (success == 0) {
        var log_buf: [512]u8 = undefined;
        var log_len: gl.Sizei = 0;
        gl.getShaderInfoLog(shader, 512, &log_len, &log_buf);
        const len: usize = @intCast(log_len);
        std.debug.print("Shader compile error: {s}\n", .{log_buf[0..len]});
    }
    return shader;
}

fn compileProgram(vert_src: [*:0]const u8, frag_src: [*:0]const u8) gl.Uint {
    const vert = compileShader(vert_src, gl.VERTEX_SHADER);
    const frag = compileShader(frag_src, gl.FRAGMENT_SHADER);

    const program = gl.createProgram();
    gl.attachShader(program, vert);
    gl.attachShader(program, frag);
    gl.linkProgram(program);

    var success: gl.Int = 0;
    gl.getProgramiv(program, gl.LINK_STATUS, &success);
    if (success == 0) {
        var log_buf: [512]u8 = undefined;
        var log_len: gl.Sizei = 0;
        gl.getProgramInfoLog(program, 512, &log_len, &log_buf);
        const len: usize = @intCast(log_len);
        std.debug.print("Shader link error: {s}\n", .{log_buf[0..len]});
    }

    gl.deleteShader(vert);
    gl.deleteShader(frag);
    return program;
}

// ============================================================================
// DrawList Renderer — renders custom draw primitives (sheet music)
// ============================================================================

const renderer_mod = @import("renderer.zig");

const prim_vert_src: [*:0]const u8 =
    \\#version 330 core
    \\layout(location = 0) in vec2 aPos;
    \\layout(location = 1) in vec4 aColor;
    \\uniform vec2 uScreen;
    \\out vec4 vColor;
    \\void main() {
    \\    vec2 ndc = aPos / uScreen * 2.0 - 1.0;
    \\    ndc.y = -ndc.y;
    \\    gl_Position = vec4(ndc, 0.0, 1.0);
    \\    vColor = aColor;
    \\}
    \\
;

const prim_frag_src: [*:0]const u8 =
    \\#version 330 core
    \\in vec4 vColor;
    \\out vec4 fragColor;
    \\void main() {
    \\    fragColor = vColor;
    \\}
    \\
;

const PrimVertex = extern struct {
    x: f32,
    y: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

fn abgrToRgba(c: u32) [4]f32 {
    return .{
        @as(f32, @floatFromInt((c >> 0) & 0xFF)) / 255.0,
        @as(f32, @floatFromInt((c >> 8) & 0xFF)) / 255.0,
        @as(f32, @floatFromInt((c >> 16) & 0xFF)) / 255.0,
        @as(f32, @floatFromInt((c >> 24) & 0xFF)) / 255.0,
    };
}

const MAX_PRIM_VERTS = 65536;

pub const DrawListRenderer = struct {
    vao: gl.Uint = 0,
    vbo: gl.Uint = 0,
    shader: gl.Uint = 0,
    screen_loc: gl.Int = 0,
    vertices: [MAX_PRIM_VERTS]PrimVertex = undefined,
    vert_count: usize = 0,
    screen_width: f32 = 1920,
    screen_height: f32 = 1080,
    font_ctx: *font_mod.FontContext,

    pub fn init(fctx: *font_mod.FontContext) DrawListRenderer {
        var self = DrawListRenderer{ .font_ctx = fctx };

        gl.genVertexArrays(1, &self.vao);
        gl.bindVertexArray(self.vao);

        gl.genBuffers(1, &self.vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.bufferData(gl.ARRAY_BUFFER, MAX_PRIM_VERTS * @sizeOf(PrimVertex), null, gl.DYNAMIC_DRAW);

        const stride: gl.Sizei = @sizeOf(PrimVertex);
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(0));
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(1, 4, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(2 * @sizeOf(f32)));
        gl.bindVertexArray(0);

        self.shader = compileProgram(prim_vert_src, prim_frag_src);
        self.screen_loc = gl.getUniformLocation(self.shader, "uScreen");
        return self;
    }

    pub fn deinit(self: *DrawListRenderer) void {
        gl.deleteVertexArrays(1, &self.vao);
        gl.deleteBuffers(1, &self.vbo);
        gl.deleteProgram(self.shader);
    }

    pub fn render(self: *DrawListRenderer, dl: *const renderer_mod.DrawList) void {
        self.vert_count = 0;

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        // Filled rects -> 2 triangles each (6 verts)
        for (dl.filled_rects[0..dl.filled_rect_count]) |rect| {
            self.ensureCapacity(6);
            const clr = abgrToRgba(rect.color);
            self.pushVertRaw(rect.x1, rect.y1, clr);
            self.pushVertRaw(rect.x2, rect.y1, clr);
            self.pushVertRaw(rect.x2, rect.y2, clr);
            self.pushVertRaw(rect.x1, rect.y1, clr);
            self.pushVertRaw(rect.x2, rect.y2, clr);
            self.pushVertRaw(rect.x1, rect.y2, clr);
        }

        // Rects (outline) -> 4 thin quads (24 verts)
        for (dl.rects[0..dl.rect_count]) |rect| {
            self.ensureCapacity(24);
            const clr = abgrToRgba(rect.color);
            const t: f32 = 1.0;
            self.pushQuadRaw(rect.x1, rect.y1, rect.x2, rect.y1 + t, clr);
            self.pushQuadRaw(rect.x1, rect.y2 - t, rect.x2, rect.y2, clr);
            self.pushQuadRaw(rect.x1, rect.y1, rect.x1 + t, rect.y2, clr);
            self.pushQuadRaw(rect.x2 - t, rect.y1, rect.x2, rect.y2, clr);
        }

        // Lines -> thin quads perpendicular to line direction (6 verts)
        for (dl.lines[0..dl.line_count]) |line| {
            const clr = abgrToRgba(line.color);
            const dx = line.x2 - line.x1;
            const dy = line.y2 - line.y1;
            const len = @sqrt(dx * dx + dy * dy);
            if (len < 0.001) continue;
            const half_t = line.thickness * 0.5;
            const nx = -dy / len * half_t;
            const ny = dx / len * half_t;

            self.ensureCapacity(6);
            self.pushVertRaw(line.x1 + nx, line.y1 + ny, clr);
            self.pushVertRaw(line.x2 + nx, line.y2 + ny, clr);
            self.pushVertRaw(line.x2 - nx, line.y2 - ny, clr);
            self.pushVertRaw(line.x1 + nx, line.y1 + ny, clr);
            self.pushVertRaw(line.x2 - nx, line.y2 - ny, clr);
            self.pushVertRaw(line.x1 - nx, line.y1 - ny, clr);
        }

        // Filled circles -> triangle fan approximation (48 verts per circle)
        for (dl.filled_circles[0..dl.filled_circle_count]) |circle| {
            const clr = abgrToRgba(circle.color);
            const segments: u32 = 16;
            self.ensureCapacity(segments * 3);
            var seg: u32 = 0;
            while (seg < segments) : (seg += 1) {
                const a0 = @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments)) * std.math.pi * 2.0;
                const a1 = @as(f32, @floatFromInt(seg + 1)) / @as(f32, @floatFromInt(segments)) * std.math.pi * 2.0;
                self.pushVertRaw(circle.cx, circle.cy, clr);
                self.pushVertRaw(circle.cx + @cos(a0) * circle.radius, circle.cy + @sin(a0) * circle.radius, clr);
                self.pushVertRaw(circle.cx + @cos(a1) * circle.radius, circle.cy + @sin(a1) * circle.radius, clr);
            }
        }

        // Circle outlines -> line segments approximation (96 verts per circle)
        for (dl.circles[0..dl.circle_count]) |circle| {
            const clr = abgrToRgba(circle.color);
            const segments: u32 = 16;
            self.ensureCapacity(segments * 6);
            var seg: u32 = 0;
            while (seg < segments) : (seg += 1) {
                const a0 = @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments)) * std.math.pi * 2.0;
                const a1 = @as(f32, @floatFromInt(seg + 1)) / @as(f32, @floatFromInt(segments)) * std.math.pi * 2.0;
                const x0 = circle.cx + @cos(a0) * circle.radius;
                const y0 = circle.cy + @sin(a0) * circle.radius;
                const x1 = circle.cx + @cos(a1) * circle.radius;
                const y1 = circle.cy + @sin(a1) * circle.radius;
                const sdx = x1 - x0;
                const sdy = y1 - y0;
                const slen = @sqrt(sdx * sdx + sdy * sdy);
                if (slen < 0.001) continue;
                const ht = circle.thickness * 0.5;
                const snx = -sdy / slen * ht;
                const sny = sdx / slen * ht;
                self.pushVertRaw(x0 + snx, y0 + sny, clr);
                self.pushVertRaw(x1 + snx, y1 + sny, clr);
                self.pushVertRaw(x1 - snx, y1 - sny, clr);
                self.pushVertRaw(x0 + snx, y0 + sny, clr);
                self.pushVertRaw(x1 - snx, y1 - sny, clr);
                self.pushVertRaw(x0 - snx, y0 - sny, clr);
            }
        }

        // Flush geometry
        self.flushPrimitives();

        // Text -> rendered using the font atlas (separate pipeline)
        self.renderTexts(dl);

        gl.disable(gl.BLEND);
    }

    fn renderTexts(self: *DrawListRenderer, dl: *const renderer_mod.DrawList) void {
        // We reuse the ClayRenderer's text pipeline approach but simpler
        // For now, render each text using the font context glyph quads
        // We need a text VAO/VBO — we'll use the same prim pipeline with text shader
        // Actually, let's just collect glyph quads and render them

        // Simple approach: use the font atlas
        const font_opt = self.font_ctx.fonts[0];
        const f = font_opt orelse return;

        var text_verts: [8192]TextVertex = undefined;
        var tv_count: usize = 0;

        for (dl.texts[0..dl.text_count]) |txt| {
            const c = abgrToRgba(txt.color);
            var quads: [64]font_mod.GlyphQuad = undefined;
            const count = self.font_ctx.getGlyphQuads(0, txt.text[0..txt.text_len], txt.x, txt.y, 16.0, 0, &quads);

            for (quads[0..count]) |q| {
                if (tv_count + 6 > 8192) break;
                text_verts[tv_count] = .{ .x = q.x0, .y = q.y0, .u = q.u0, .v = q.v0, .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                tv_count += 1;
                text_verts[tv_count] = .{ .x = q.x1, .y = q.y0, .u = q.u1, .v = q.v0, .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                tv_count += 1;
                text_verts[tv_count] = .{ .x = q.x1, .y = q.y1, .u = q.u1, .v = q.v1, .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                tv_count += 1;
                text_verts[tv_count] = .{ .x = q.x0, .y = q.y0, .u = q.u0, .v = q.v0, .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                tv_count += 1;
                text_verts[tv_count] = .{ .x = q.x1, .y = q.y1, .u = q.u1, .v = q.v1, .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                tv_count += 1;
                text_verts[tv_count] = .{ .x = q.x0, .y = q.y1, .u = q.u0, .v = q.v1, .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                tv_count += 1;
            }
        }

        if (tv_count == 0) return;

        // Use the text shader from ClayRenderer — but we don't have direct access.
        // Create our own text pipeline reusing the same shaders.
        // For simplicity, we'll use the text_shader from a companion ClayRenderer.
        // Actually, let's just create a standalone text pipeline here.
        // We already have the text shader sources at module level.

        const text_prog = compileProgram(text_vert_src, text_frag_src);
        defer gl.deleteProgram(text_prog);

        var tvao: gl.Uint = 0;
        var tvbo: gl.Uint = 0;
        gl.genVertexArrays(1, &tvao);
        gl.genBuffers(1, &tvbo);
        defer gl.deleteVertexArrays(1, &tvao);
        defer gl.deleteBuffers(1, &tvbo);

        gl.bindVertexArray(tvao);
        gl.bindBuffer(gl.ARRAY_BUFFER, tvbo);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(tv_count * @sizeOf(TextVertex)), @ptrCast(&text_verts), gl.DYNAMIC_DRAW);

        const tstride: gl.Sizei = @sizeOf(TextVertex);
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, tstride, @ptrFromInt(0));
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, tstride, @ptrFromInt(2 * @sizeOf(f32)));
        gl.enableVertexAttribArray(2);
        gl.vertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, tstride, @ptrFromInt(4 * @sizeOf(f32)));

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, f.atlas_texture);

        gl.useProgram(text_prog);
        gl.uniform2f(gl.getUniformLocation(text_prog, "uScreen"), self.screen_width, self.screen_height);
        gl.uniform1i(gl.getUniformLocation(text_prog, "uFontAtlas"), 0);

        gl.drawArrays(gl.TRIANGLES, 0, @intCast(tv_count));

        gl.bindVertexArray(0);
        gl.bindTexture(gl.TEXTURE_2D, 0);
    }

    /// Flush if fewer than `needed` vertex slots remain.
    /// Call BEFORE emitting a complete primitive to prevent mid-primitive splits.
    fn ensureCapacity(self: *DrawListRenderer, needed: usize) void {
        if (self.vert_count + needed > MAX_PRIM_VERTS) self.flushPrimitives();
    }

    /// Push a single vertex. Caller must have called ensureCapacity first.
    fn pushVertRaw(self: *DrawListRenderer, x: f32, y: f32, clr: [4]f32) void {
        self.vertices[self.vert_count] = .{ .x = x, .y = y, .r = clr[0], .g = clr[1], .b = clr[2], .a = clr[3] };
        self.vert_count += 1;
    }

    fn pushQuadRaw(self: *DrawListRenderer, x1: f32, y1: f32, x2: f32, y2: f32, clr: [4]f32) void {
        self.pushVertRaw(x1, y1, clr);
        self.pushVertRaw(x2, y1, clr);
        self.pushVertRaw(x2, y2, clr);
        self.pushVertRaw(x1, y1, clr);
        self.pushVertRaw(x2, y2, clr);
        self.pushVertRaw(x1, y2, clr);
    }

    fn flushPrimitives(self: *DrawListRenderer) void {
        if (self.vert_count == 0) return;

        gl.useProgram(self.shader);
        gl.uniform2f(self.screen_loc, self.screen_width, self.screen_height);

        gl.bindVertexArray(self.vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.bufferSubData(gl.ARRAY_BUFFER, 0, @intCast(self.vert_count * @sizeOf(PrimVertex)), @ptrCast(&self.vertices));

        gl.drawArrays(gl.TRIANGLES, 0, @intCast(self.vert_count));
        gl.bindVertexArray(0);

        self.vert_count = 0;
    }
};
