<p align="center"><img src="Icon/icon_1024.png" width="128" alt="WindowMirror icon"></p>

<h1 align="center">WindowMirror</h1>

<p align="center">Mirror a single window from your main display to a second screen in real time, and annotate it with a laser pointer, pen or highlighter.</p>

<p align="center">English · <a href="README_zh.md">简体中文</a></p>

---

WindowMirror is built for demos, lectures and meetings. It puts one window on a projector or external monitor. The audience sees only that window, and the rest of your main screen stays private.

> The app's menus are currently in Chinese. This guide gives each menu item's Chinese label together with an English translation.

## Features

- **Single-window mirroring:** Captures at 60 fps and at the source window's native resolution, using ScreenCaptureKit. The mirror keeps updating while the window is covered or partly off screen.
- **Full-screen output:** The mirror fills the second display borderless and stays on top. It never takes focus away from your main screen. With only one display, the mirror opens as a regular window instead.
- **Fit the source window to the second screen:** One click resizes the source window to the second screen's exact pixel size (1:1). It can also match only the aspect ratio, so the mirror fills the screen with no black bars.
- **HDR and wide color:** Captures in half-float extended Display P3 to keep highlights, and shows the result with EDR on the second screen. It falls back to SDR when HDR capture isn't available.
- **Annotations:** Draw with a laser pointer, pen or highlighter on the source window, and the mirror shows the same marks. Comes with global shortcuts, several colors, undo and optional auto-fading ink.
- **Scaling modes:** Fit, fill, stretch, or native pixels (1:1, centered).
- **Menu bar app:** Has no Dock icon. Everything is in the menu bar icon.

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
| Screen & System Audio Recording | Listing windows and capturing them | Only "点选窗口…" (Pick window…) works, because it uses the system picker, which needs no permission |
| Accessibility | Resizing the source window to fit the second screen | Resizing is unavailable, and everything else works |

Both are under System Settings › Privacy & Security.

> **Note:** The app is ad-hoc signed, so its signature changes on every rebuild and macOS treats each build as a new app. After rebuilding, remove the old entries in both settings above and add the app again. To avoid this, sign with a stable code-signing certificate by replacing `--sign -` in `build.sh` with your certificate's name.

## Usage

Click the menu bar icon, the one with two overlapping rectangles:

1. **Choose a window:** Click "点选窗口…" (Pick window…, ⌘P) and click the window you want. Or choose one from "从主屏窗口列表选择" (Choose from main-screen windows).
2. **Target display:** The first secondary display is used by default. You can pick a different one under "目标显示器" (Target display).
3. **Stop:** Click "停止镜像" (Stop mirroring). Or click the mirror once and press Esc. Mirroring also stops when the source window closes.

While mirroring, the menu shows the source and target pixel sizes and the current scale factor.

### Fit the source window to the second screen

These options are under "按副屏调整源窗口" (Fit source window to second screen).

| Option | Shortcut | Result |
|---|---|---|
| 像素 1:1 (Pixel 1:1) | ⌃⌥M | Source window matches the second screen's pixel size, the sharpest result |
| 同比例，尽量大 (Same ratio, largest) | ⌃⌥R | Largest size at the second screen's aspect ratio that fits the main screen's visible area |
| 同比例，保持当前宽度 (Same ratio, keep width) | — | Keeps the width and changes only the height |
| 同比例，保持当前高度 (Same ratio, keep height) | — | Keeps the height and changes only the width |

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
- **Colors and fading:** Set the color under "标注" (Annotate), and turn on "笔迹几秒后自动消失" (Fade strokes after a few seconds) there.
- **Pen and highlighter:** The annotation layer takes the mouse, so you can't click the source window while drawing. Switch to the laser pointer or exit annotation mode to use the window again.

## Known limitations

- **Minimized windows:** The mirror stops updating while the source window is minimized.
- **Color differences:** The two displays have different panels, and True Tone may be on. The mirror's colors can't match the source screen exactly.
- **Physical pixels:** If the second screen uses a scaled resolution, macOS scales the image again, so physical pixels aren't strictly 1:1.
- **Projects in iCloud folders:** macOS adds extended attributes to `.app` bundles in iCloud-synced folders, and those make code signing fail. That's why build output goes to `~/Library/Caches` instead of the project folder.

## Project layout

```
Sources/main.swift        Menu bar app, capture engine, mirror window, source-window resizing
Sources/Annotation.swift  Annotations: model, rendering, overlay layer, global shortcuts
Icon/draw_icon.swift      Draws the app icon with Core Graphics
Icon/AppIcon.icns         Generated icon
build.sh / install.sh     Build and install scripts
```

To redraw the icon, run:

```bash
swift Icon/draw_icon.swift Icon/icon_1024.png
```

Then use `sips` and `iconutil` to build `AppIcon.icns` from it.

## Debugging

Launch the app with environment variables, and the log goes to standard error:

```bash
open --env WM_DEBUG=1 --stderr /tmp/wm.log /Applications/WindowMirror.app
```

| Variable | Effect |
|---|---|
| `WM_DEBUG=1` | Write log output |
| `WM_AUTOSTART=<app name fragment>` | On launch, mirror that app's first window on the main screen |
| `WM_SNAPSHOT=<path.png>` | Save frame 30 as a PNG |
| `WM_AUTOMATCH=<0-3>` | Fit the source window automatically; 0 to 3 are the four options in the table above |
| `WM_TESTDRAW=<directory>` | Inject test annotations and save screenshots of the app's own windows to that directory |

## License

[MIT](LICENSE)
