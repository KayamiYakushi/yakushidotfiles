# 薬 Yakushi Dotfiles

A compact Hyprland desktop setup with a glassy **Yakushi Settings** control panel, minimal Waybar, Raycast-style Rofi launcher, and portable per-machine configuration.

<p align="center">
  <img src="assets/preview.png" alt="Yakushi Dotfiles preview">
</p>

## Highlights

- **Yakushi Settings** — `SUPER + I`
- Appearance controls for panel, app launcher, and top bar opacity
- Editable keybinds with persistent **ON / OFF** state
- Searchable installed XKB keyboard layouts
- Pointer sensitivity control
- Monitor configuration with:
  - resolution and refresh-rate selection
  - scale
  - exact X/Y positioning
  - draggable display layout
  - machine-local persistence
- Night Light control with visible Kelvin value
- Raycast-style Rofi launcher
- Wallpaper selector — `SUPER + W`
- Minimal Waybar:
  - Left: RAM, CPU usage, CPU temperature, GPU temperature
  - Center: currently playing
  - Right: volume, clock, power
- Area screenshot + clipboard — `SUPER + SHIFT + S`

## Installation

Clone the repository:

```fish
git clone https://github.com/KayamiYakushi/yakushidotfiles.git
cd yakushidotfiles
fish install.fish
```

The installer creates a timestamped backup under `~/YakushiBackups/` before replacing managed configuration.

## Runtime tools

Yakushi Dotfiles expects the following tools to be available:

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
- a Nerd Font

Recommended fonts:

- `JetBrainsMono Nerd Font`
- `Noto Sans CJK JP`

The default browser command in this setup is Zen Browser via Flatpak:

```text
flatpak run app.zen_browser.zen
```

Change the `browser` command in your Hyprland configuration if you use something else.

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

## Portable configuration

Machine-specific monitor state is intentionally **not tracked**.

Yakushi Settings stores it locally in:

```text
~/.config/hypr/monitors.local.lua
~/.config/hypr/yakushi-monitor-state.local.json
```

The tracked `monitors.lua` stays generic, so cloning this repository on another computer does not inherit the original machine's display connectors, resolutions, refresh rates, or positions.

Wallpaper paths use the current user's home directory instead of a hardcoded username.

## Wallpaper selector

Put wallpapers in:

```text
~/Pictures/Wallpapers/
```

Then press:

```text
SUPER + W
```

The selector generates thumbnails under the current user's cache directory and applies the selected wallpaper with `awww`.

## Credits

Yakushi Dotfiles is based on and substantially modifies [43PR/dotfiles](https://github.com/43PR/dotfiles).

The upstream project is distributed under the MIT License. Its copyright and license notice are preserved.

## License

MIT. See [`LICENSE`](LICENSE).
