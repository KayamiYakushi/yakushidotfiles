# 薬 Yakushi Dotfiles

A compact Hyprland desktop setup built around **Yakushi Settings**, a minimal glassy Waybar, a Raycast-style Rofi launcher, and practical desktop controls.

<p align="center">
  <img src="assets/preview.png" alt="Yakushi Dotfiles preview">
</p>

## Highlights

- **Yakushi Settings** — `SUPER + I`
- Appearance controls for:
  - settings panel opacity
  - Rofi launcher opacity
  - Waybar opacity
- Editable keybinds with persistent **ON / OFF** state
- Searchable installed XKB layouts
- Pointer sensitivity control
- Monitor configuration with:
  - resolution
  - refresh rate
  - scale
  - exact X/Y position
  - draggable display layout
  - machine-local persistence
- Night Light control with visible Kelvin value
- Raycast-style Rofi launcher
- Recursive wallpaper selector — `SUPER + W`
- Minimal Waybar:
  - Left: RAM, CPU usage, CPU temperature, GPU temperature
  - Center: currently playing
  - Right: volume, clock, power
- Area screenshot + clipboard — `SUPER + SHIFT + S`

## Preview

The screenshot above shows the current Yakushi desktop layout and Yakushi Settings panel.

## Installation

Clone the repository:

```fish
git clone https://github.com/KayamiYakushi/yakushidotfiles.git
cd yakushidotfiles
fish install.fish
```

The installer creates a timestamped backup under:

```text
~/YakushiBackups/
```

before replacing the managed configuration directories.

## Runtime tools

Yakushi Dotfiles expects these tools to be available:

- Hyprland
- Quickshell
- Waybar
- Rofi
- Python 3
- Kitty
- Thunar
- Dunst
- NetworkManager / `nm-applet`
- `wl-clipboard`
- `cliphist`
- `grim`
- `slurp`
- `brightnessctl`
- `gammastep`
- `playerctl`
- `pavucontrol`
- `wlogout`
- `awww`
- `jq`
- ImageMagick
- Nerd Fonts

Recommended fonts:

- `JetBrainsMono Nerd Font`
- `Noto Sans CJK JP`

The default browser command in this setup is Zen Browser via Flatpak:

```text
flatpak run app.zen_browser.zen
```

Change the browser command in your Hyprland configuration if you use a different browser.

## Main shortcuts

| Shortcut | Action |
| --- | --- |
| `SUPER + I` | Yakushi Settings |
| `SUPER + D` | App launcher |
| `SUPER + T` | Terminal |
| `SUPER + E` | File manager |
| `SUPER + B` | Browser |
| `SUPER + Q` | Close window |
| `SUPER + V` | Clipboard history |
| `SUPER + SHIFT + S` | Area screenshot + clipboard |
| `SUPER + W` | Wallpaper selector |
| `SUPER + TAB` | Lock screen |

## Wallpaper selector

`SUPER + W` recursively scans:

```text
~/Documents
```

for:

```text
.jpg
.jpeg
.png
.webp
```

A temporary index is generated under:

```text
~/.cache/quickshell/wallpaper-index/
```

The real image files stay in `~/Documents`; the index only contains generated links used by the selector.

Thumbnails are cached under:

```text
~/.cache/quickshell/thumbs/
```

The selected wallpaper is applied with `awww`.

## Portable monitor configuration

Machine-specific monitor state is intentionally **not tracked**.

Yakushi Settings stores it locally in:

```text
~/.config/hypr/monitors.local.lua
~/.config/hypr/yakushi-monitor-state.local.json
```

The tracked `monitors.lua` stays generic so another user's machine does not inherit the original monitor names, resolutions, refresh rates, or positions.

## Notes

- Disabled keybinds keep their metadata while releasing the shortcut for another active bind.
- Rofi opacity changes the launcher background alpha.
- Waybar opacity controls the three main bar containers together.
- CPU and GPU temperature modules discover their sensors dynamically instead of relying on a fixed `hwmonN` path.
- User-specific display connectors are kept out of the repository.

## Credits

Yakushi Dotfiles is based on and substantially modifies [43PR/dotfiles](https://github.com/43PR/dotfiles).

The original project is distributed under the MIT License. Its copyright and license notice are preserved.

## License

MIT. See [`LICENSE`](LICENSE).
