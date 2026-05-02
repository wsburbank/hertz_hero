const clay = @import("clay");

/// Neon dark theme — ported from the ImGui applyNeonTheme() colors.
/// Clay colors use 0-255 float RGBA convention.
pub const Color = clay.Color;

// Backgrounds — very dark blue-tinted
pub const bg_window = Color{ 20, 20, 31, 245 };
pub const bg_child = Color{ 18, 18, 28, 255 };
pub const bg_popup = Color{ 26, 26, 36, 245 };

// Text
pub const text_primary = Color{ 235, 237, 245, 255 };
pub const text_disabled = Color{ 102, 107, 122, 255 };

// Borders — subtle neon glow
pub const border_default = Color{ 0, 89, 140, 128 };
pub const border_active = Color{ 0, 170, 255, 255 };

// Neon accent: RGB(0, 170, 255) = #00AAFF
pub const neon = Color{ 0, 170, 255, 255 };
pub const neon_dim = Color{ 0, 115, 191, 255 };
pub const neon_bright = Color{ 51, 199, 255, 255 };
pub const neon_subtle = Color{ 0, 64, 115, 153 };

// Buttons
pub const button_default = Color{ 0, 115, 191, 255 };
pub const button_hover = Color{ 0, 170, 255, 255 };
pub const button_active = Color{ 51, 199, 255, 255 };

// Frame (input fields, slider tracks)
pub const frame_bg = Color{ 26, 31, 46, 255 };
pub const frame_bg_hover = Color{ 31, 41, 64, 255 };
pub const frame_bg_active = Color{ 20, 51, 89, 255 };

// Headers (tree nodes, collapsible sections)
pub const header_default = Color{ 0, 64, 115, 153 };
pub const header_hover = Color{ 0, 102, 166, 179 };
pub const header_active = Color{ 0, 115, 191, 255 };

// Sliders
pub const slider_track = Color{ 26, 31, 46, 255 };
pub const slider_grab = Color{ 0, 170, 255, 255 };
pub const slider_grab_active = Color{ 51, 199, 255, 255 };

// Checkbox
pub const checkbox_bg = Color{ 26, 31, 46, 255 };
pub const checkbox_check = Color{ 51, 199, 255, 255 };

// Scrollbar
pub const scrollbar_bg = Color{ 15, 15, 26, 204 };
pub const scrollbar_grab = Color{ 38, 51, 77, 255 };
pub const scrollbar_grab_hover = Color{ 0, 115, 191, 255 };

// Separator
pub const separator_default = Color{ 0, 77, 128, 102 };

// Title bar
pub const title_bg = Color{ 15, 15, 26, 255 };
pub const title_bg_active = Color{ 0, 51, 89, 255 };

// Track row borders (Clay RGBA)
pub const track_border = Color{ 0, 77, 128, 128 };
pub const track_bg_even = Color{ 22, 22, 34, 255 };
pub const track_bg_odd = Color{ 18, 18, 28, 255 };

// Transparent
pub const transparent = Color{ 0, 0, 0, 0 };

// Corner radii
pub const radius_window: f32 = 8.0;
pub const radius_child: f32 = 6.0;
pub const radius_frame: f32 = 6.0;
pub const radius_popup: f32 = 6.0;
pub const radius_button: f32 = 6.0;
pub const radius_scrollbar: f32 = 8.0;
pub const radius_grab: f32 = 4.0;
pub const radius_tab: f32 = 6.0;

// Sheet music colors (u32 ABGR format for custom draw list)
pub const col_line: u32 = 0xFF666680;
pub const col_bar: u32 = 0xFF555570;
pub const col_note: u32 = 0xFFDDE0F0;
pub const col_stem: u32 = 0xFFAAB0CC;
pub const col_clef: u32 = 0xFF8090BB;
pub const col_label: u32 = 0xFF00CCFF;
pub const col_cursor: u32 = 0x8800AAFF;
pub const col_play: u32 = 0xFF00FFAA;
pub const col_play_glow: u32 = 0x6000FFAA;
pub const col_play_bar: u32 = 0x3500FFAA;
pub const col_master_line: u32 = 0xFF6688CC;
pub const col_master_label: u32 = 0xFF88BBFF;
pub const col_panel_bg: u32 = 0xF0101018;
pub const col_panel_border: u32 = 0xFF003366;
pub const col_track_border: u32 = 0x80804D00; // matches track_border in ABGR
pub const col_track_bg_even: u32 = 0xFF221616; // subtle even row tint
pub const col_track_bg_odd: u32 = 0xFF1C1212; // subtle odd row tint
