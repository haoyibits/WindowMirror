<p align="center"><img src="Icon/icon_1024.png?v=2" width="128" alt="WindowMirror icon"></p>

<h1 align="center">WindowMirror</h1>

<p align="center">Mirror a single window from your main display to a second screen in real time, and annotate it with a laser pointer, pen or highlighter.</p>

<p align="center">English · <a href="README_zh.md">简体中文</a></p>

---

WindowMirror is built for demos, lectures and meetings. It puts one window on a projector or external monitor. The audience sees only that window, and the rest of your main screen stays private.

## Features

- **Single-window mirroring:** Captures at 60 fps and at the source window's native resolution, using ScreenCaptureKit. The mirror keeps updating while the window is covered or partly off screen.
- **Full-screen output:** The mirror fills the second display borderless and stays on top. It never takes focus away from your main screen. With only one display, the mirror opens as a regular window instead.
- **Fit the source window to the second screen:** One click resizes the source window to the second screen's exact pixel size (1:1). It can also match only the aspect ratio, so the mirror fills the screen with no black bars.
- **HDR and wide color:** Captures in half-float extended Display P3 to keep highlights, and shows the result with EDR on the second screen. It falls back to SDR when HDR capture isn't available.
- **Annotations:** Draw with a laser pointer, pen or highlighter on the source window, and the mirror shows the same marks. Comes with global shortcuts, several colors, undo and optional auto-fading ink.
- **Scaling modes:** Fit, fill, stretch, or native pixels (1:1, centered).
- **Menu bar app:** Has no Dock icon. Everything is in the menu bar icon.
- **English and Chinese:** The interface follows your system language, and you can switch it from the menu.

## Installation

You need macOS 14 or later, plus the Xcode Command Line Tools for `swiftc`.

```bash
git clone https://github.com/haoyibits/WindowMirror.git
cd WindowMirror
./install.sh
```

`install.sh` builds and signs the app, installs it to `/Applications`, and launches it. To build without installing, run `./build.sh`. The output goes to `~/Library/Caches/WindowMirror/`.

### Permissions

| Permission | Used for | Without it |
|---|---|---|
| Screen & System Audio Recording | Listing windows and capturing them | Only "Pick Window…" works, because it uses the system picker, which needs no permission |
| Accessibility | Resizing the source window to fit the second screen | Resizing is unavailable, and everything else works |

Both are under System Settings › Privacy & Security.

> **Note:** The app is ad-hoc signed, so its signature changes on every rebuild and macOS treats each build as a new app. After rebuilding, remove the old entries in both settings above and add the app again. To avoid this, sign with a stable code-signing certificate by replacing `--sign -` in `build.sh` with your certificate's name.

## Usage

Click the menu bar icon, the one with two overlapping rectangles:

1. **Choose a window:** Click "Pick Window…" (⌘P) and click the window you want. Or choose one from "Choose from Main-Screen Windows".
2. **Target display:** The first secondary display is used by default. You can pick a different one under "Target Display".
3. **Stop:** Click "Stop Mirroring". Or click the mirror once and press Esc. Mirroring also stops when the source window closes.

While mirroring, the menu shows the source and target pixel sizes and the current scale factor.

### Fit the source window to the second screen

These options are under "Fit Source Window to Target".

| Option | Shortcut | Result |
|---|---|---|
| Pixel 1:1 | ⌃⌥M | Source window matches the second screen's pixel size, the sharpest result |
| Same Ratio, Largest | ⌃⌥R | Largest size at the second screen's aspect ratio that fits the main screen's visible area |
| Same Ratio, Keep Width | — | Keeps the width and changes only the height |
| Same Ratio, Keep Height | — | Keeps the height and changes only the width |

If the window doesn't fit, it is scaled down proportionally and moved back into the visible area. Some apps limit window sizes; for example, terminals resize in whole rows and columns. In that case the ratio can be slightly off, and the app shows how far off it is.

### Annotations

You draw on the source window on your main screen, and the mirror shows the same marks. The shortcuts work from any app:

| Shortcut | Action |
|---|---|
| ⌃⌥L | Laser pointer. Clicks pass through to the source window, and the system cursor is hidden in the mirror |
| ⌃⌥D | Pen |
| ⌃⌥H | Highlighter |
| ⌃⌥Z | Undo last stroke |
| ⌃⌥C | Clear all |
| ⌃⌥X | Exit annotation mode and clear all strokes |

- **Switching and exiting:** Pressing the current tool's shortcut again also exits annotation mode.
- **Colors and fading:** Set the color under "Annotate", and turn on "Fade Strokes After a Few Seconds" there.
- **Pen and highlighter:** The annotation layer takes the mouse, so you can't click the source window while drawing. Switch to the laser pointer or exit annotation mode to use the window again.

### Language

The interface is English by default. If your system's preferred language is Chinese, it switches to Chinese automatically. To choose a language yourself, use "Language / 语言" in the menu. It offers Follow System, English and 简体中文, and the change applies the next time you open the menu.

## Known limitations

- **Minimized windows:** The mirror stops updating while the source window is minimized.
- **Color differences:** The two displays have different panels, and True Tone may be on. The mirror's colors can't match the source screen exactly.
- **Physical pixels:** If the second screen uses a scaled resolution, macOS scales the image again, so physical pixels aren't strictly 1:1.
- **Projects in iCloud folders:** macOS adds extended attributes to `.app` bundles in iCloud-synced folders, and those make code signing fail. That's why build output goes to `~/Library/Caches` instead of the project folder.

## Project layout

```
Sources/main.swift        Menu bar app, capture engine, mirror window, source-window resizing, localization
Sources/Annotation.swift  Annotations: model, rendering, overlay layer, global shortcuts
Icon/draw_icon.swift      Draws the app icon with Core Graphics
Icon/AppIcon.icns         Generated icon
Resources/*.lproj         Localized app name
build.sh / install.sh     Build and install scripts
```

## License

[MIT](LICENSE)
