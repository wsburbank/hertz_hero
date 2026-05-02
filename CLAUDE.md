# MIDI-to-Sheet Music Gamifier

## Project Overview
A high-performance desktop application built with Zig and Dear ImGui that converts MIDI files into readable sheet music and provides a gamified practice experience.

## Core Features (Updated)
* **MIDI Management:** Import, track muting, volume control, and staff grouping.
* **Notation Engine:** MIDI-to-Notation conversion with Quantization (8th/16th note snapping) and Transposition support.
* **Gamification:** Real-time microphone input with latency calibration and "Guitar Hero" style scoring.
* **Visuals:** High-contrast Dark Mode, note-head labels, and post-performance mistake heatmaps.

---

## Technical Insight: Zig + Dear ImGui
This stack offers the best "Performance-to-Binary Size" ratio. Zig’s C interoperability allows you to use industry-standard audio and MIDI libraries without the overhead of a heavy runtime.

### 1. Recommended Libraries
To avoid reinventing the wheel while keeping the app slim, use these C/C++ libraries via Zig:

| Category | Library | Why? |
| :--- | :--- | :--- |
| **GUI Framework** | [zgui](https://github.com/zig-gamedev/zgui) | High-level Zig bindings for Dear ImGui. Includes ImPlot for scoring graphs. |
| **Audio Engine** | [miniaudio](https://miniaud.io/) | Single-header C library for audio playback and mic input. Very small footprint. |
| **MIDI Parsing** | [libremidi](https://github.com/jcelerier/libremidi) | Modern C++ library for both MIDI file parsing and real-time MIDI I/O. |
| **Pitch Detection** | [FFTW3](https://www.fftw.org/) | The fastest library for Fast Fourier Transforms (FFT) to convert mic input to frequency. |
| **Window/Inputs** | [zglfw](https://github.com/zig-gamedev/zglfw) | Zig bindings for GLFW to handle window creation and hardware events. |

### 2. Setup & Installation (Zig 0.13.0+)
Zig uses a declarative build system. You can manage dependencies using the `build.zig.zon` file.

Step 2: Add Dependencies
Add your libraries to build.zig.zon using zig fetch --save <url>. For example:

Bash
zig fetch --save [https://github.com/zig-gamedev/zgui/archive/main.tar.gz](https://github.com/zig-gamedev/zgui/archive/main.tar.gz)
Step 3: Configure build.zig
In your build.zig, link the C libraries and the ImGui modules:

Code snippet
const zgui = b.dependency("zgui", .{
    .shared = false,
    .with_implot = true,
});
exe.root_module.addImport("zgui", zgui.module("root"));
exe.linkLibrary(zgui.artifact("imgui"));
exe.linkLibC(); // Required for miniaudio and FFTW
3. Implementation Strategy
Rendering: Instead of a heavy engraving engine, use ImGui’s ImDrawList. It allows you to draw musical symbols (stems, note heads, lines) directly as vertex buffers, which is incredibly fast for a scrolling "Guitar Hero" interface.

Timing: Use a high-resolution timer (provided by Zig's std.time) to sync the MIDI playback clock with the UI render loop.

4. Documentation & Resources
Zig Language: ziglang.org/documentation

Dear ImGui Manual: pthom.github.io/imgui_manual_online

zgui (Zig Bindings): github.com/zig-gamedev/zgui

Miniaudio Guide: miniaud.io/docs/manual/


### Why this works for you:
1.  **Binary Size:** A basic `zgui` app usually compiles to **under 5MB**. Even with MIDI and Audio libraries, you’ll likely stay under 15MB, whereas an Electron/Electrobun app would be 50MB+.
2.  **Latency:** Since you are using Zig, you can process the microphone's audio buffer in a dedicated high-priority thread. This is crucial for a "Guitar Hero" clone—if the scoring is off by even 50ms, the game feels broken.
3.  **Future-Proofing:** Since you're interested in hardware and DIY electronics, Zig's ability to compile for "bare metal" or embedded systems means you could eventually port parts of this logic to custom hardware controllers.

[Fast Fourier Transform (FFT) explained](https://www.youtube.com/watch?v=nmgFG7PUHfo)
This video explains how sound waves are converted into frequencies, which is the foundational math you'll need to implement your microphone-based scoring system.

How deep into the "sheet music" side do you want to go? Are we talking basic horizontal scrolling "notes on lines," or do you need full professional page engraving?

**Step 1: Initialize Project**
```bash
mkdir midi-app && cd midi-app
zig init

# MIDI-to-Sheet Music Gamifier

## Project Overview
A desktop application that converts MIDI files into readable sheet music while providing a gamified "play-along" experience using real-time microphone input.

## Core Features

### 1. File & Track Management
* **MIDI Import:** Ability to open and parse standard `.mid` or `.midi` files.
* **Track Selection:** * Toggle visibility for individual tracks in the sheet music display.
    * Mute/Unmute specific tracks for audio playback.
    * Individual volume sliders for each track.
* **Staff Lumping:** Option to group multiple MIDI tracks onto a single staff (e.g., merging separate "Left Hand" and "Right Hand" tracks into a Grand Staff).
* **Quantization:** Snap "humanized" MIDI data to the nearest 8th or 16th note to ensure clean, readable notation.

### 2. Sheet Music Rendering
* **Dynamic Notation:** Convert MIDI pitch and duration data into standard musical notation.
* **Tempo Control:** Global BPM adjustment that affects both audio playback and notation scrolling speed.
* **Key Signature & Transposition:** Auto-detect or manually set the key signature; allow real-time transposition of the score.
* **Clef Selection:** Manually override or auto-detect Treble, Bass, or Alto clefs based on track range.
* **Accessibility:** Optional note-head labels (A, B, C#) and a high-contrast Dark Mode for reduced eye strain.

### 3. Audio & Gamification
* **Integrated Synth:** High-quality playback using internal soundfonts or system MIDI.
* **Microphone Input & Calibration:** Real-time pitch detection with a dedicated latency calibration tool to sync audio processing with the UI.
* **Scoring System:** * Accuracy (Pitch) and Timing (Perfect/Great/Good/Miss).
    * Streak multipliers for consecutive correct notes.
* **Visual Feedback:** Real-time green/red highlighting on the staff.
* **Mistake Analysis:** Generate a heatmap of the score post-performance to show which measures need more practice.

## Stretch Features
* **MIDI Input Support:** Support for USB/MIDI keyboards for 1:1 input accuracy.
* **PDF Export:** Printable notation output.
* **Drill/Loop Mode:** Practice specific measures in a loop.
* **Leaderboards:** Local high-score tracking per file.