# 薬 Dotfiles

My motto is: neither AUR or any non-official arch repos used, as optimized as possible, no background service runs unless its needed.

A compact Hyprland desktop setup built around a custom **Settings** panel, an island-style top bar, a Raycast-style Rofi launcher, and practical desktop controls.

<p align="center">
  <img src="assets/preview.png" alt="Desktop preview">
</p>

## Highlights

The top bar is an **island**: a small notch hanging from the top edge of the screen, built with Quickshell.
It shows workspaces, RAM usage (GB), CPU usage (%), CPU temperature, GPU temperature, now playing,
volume, date (`Fri 23 Oct`), time (with seconds) and a power button.

- Configure it in `SUPER + I` → **Top Bar**: turn any module on or off, reorder modules with the
  arrows, show or hide seconds, switch between 24- and 12-hour time, change the opacity — all
  applied instantly.
- Hover the song and a now-playing card drops down right below it (the rest of the island
  stays put): cover art, title and artist, a live music visualizer (cava), a seekable progress
  bar with elapsed / remaining time, and previous / play-pause / next. The visualizer can run
  on hover (default), always, or never.
- Hover the volume for a slider.
- Prefer the classic look? Pick **Waybar** under Top Bar → Style. Seconds and opacity carry over.
- `SUPER + SHIFT + W` hides or shows the bar.
- The power button (or ``SUPER + ` ``) opens a power menu that drops down from the island:
  Lock, Suspend, Log out, Restart, Shut down, plus uptime. Log out / Restart / Shut down ask for
  a second click, so a stray click is harmless; arrows + Enter and Esc work from the keyboard.
  With the Waybar style the same menu appears as a matching rofi panel.
- `SUPER + I` → **Appearance**: ten accent colours plus any custom `#rrggbb`, window gaps
  (screen edges and between windows), rounded or sharp corners with an adjustable radius,
  an optional window shadow with adjustable size, and an optional window border whose colour
  follows the accent or any `#rrggbb`. Shadow and border are stored in the machine-local
  `~/.config/hypr/window.local.lua`.
- Island controls: click a workspace dot to switch (scroll to step through), click the song to
  play/pause (right-click: next, middle-click: previous), click volume to mute (scroll: ±5%,
  right-click: mixer), hover RAM for used / total.

- Area screenshot + clipboard — `SUPER + SHIFT + S`

## Preview

The screenshot above shows the current desktop layout and the Settings panel.

## Installation

Clone the repository and run the installer:

```fish
git clone https://github.com/KayamiYakushi/yakushidotfiles.git
cd yakushidotfiles
sh install.sh
```

`install.sh` bootstraps Fish when needed, then `install.fish` installs the required packages from the official Arch repositories,
creates a timestamped backup, installs the desktop configuration, configures the
SDDM theme, and enables the required services. No AUR helper is required.

The installer creates a timestamped backup under:

```text
~/YakushiBackups/
```

before replacing the managed configuration directories.

The installer also detects your system keyboard layout (X11 layout, then console
keymap, falling back to `us`) and writes it into `~/.config/hypr/hyprland.lua`.
You can change it at any time in **Settings → Input**.

## Runtime tools

These dotfiles use the following runtime tools. The installer installs them automatically from the official Arch repositories:

- Hyprland
- Quickshell
- Waybar
- Rofi
- Python 3
- Kitty
- Nautilus
- Firefox
- NetworkManager / `nmcli`
- BlueZ / `bluetoothctl`
- `wl-clipboard`
- `cliphist`
- `grim`
- `slurp`
- `brightnessctl`
- `hyprsunset`
- `hyprlock`
- `playerctl`
- `pavucontrol`
- `awww`
- `jq`
- ImageMagick
- SDDM
- `hyprpolkitagent`
- `qt6ct`
- Nerd Fonts

Recommended fonts:

- `JetBrainsMono Nerd Font`
- `Noto Sans CJK JP`

The default browser is Firefox, installed automatically from the official Arch repositories.

Change the browser command in your Hyprland configuration if you prefer a different browser.

## Main shortcuts (THEY ARE ALL EASY TO CHANGE)

| Shortcut | Action |
| --- | --- |
| `SUPER + I` | Settings |
| `SUPER + SPACE` | App launcher |
| `SUPER + Q` | Terminal |
| `SUPER + E` | File manager |
| `SUPER + B` | Browser |
| `SUPER + C` | Close window |
| `SUPER + V` | Clipboard history |
| `SUPER + SHIFT + S` | Area screenshot + clipboard |
| `SUPER + W` | Wallpaper selector |
| `SUPER + TAB` | Lock screen |
| `SUPER + GRAVE` | Power menu |

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

Settings stores it locally in:

```text
~/.config/hypr/monitors.local.lua
~/.config/hypr/yakushi-monitor-state.local.json
```

The tracked `monitors.lua` stays generic so another user's machine does not inherit the original monitor names, resolutions, refresh rates, or positions.

## Runtime architecture

- Settings runs on demand and exits completely when closed.
- The Volume OSD runs in a short-lived Quickshell process and exits after use.
- The island bar is event-driven: workspaces (Hyprland IPC), now playing (MPRIS), volume
  (PipeWire) and the clock update only when something changes. The only timer reads
  `/proc/stat`, `/proc/meminfo` and two hwmon files every 2 seconds, without spawning processes;
  modules that are turned off are not read. The clock ticks every second only while seconds are shown.
- cava runs only while the visualizer is on screen and music is playing; otherwise no process runs.
- Top bar settings live in `~/.config/quickshell/yakushi-topbar.local.json` (machine-local).
- `~/.config/quickshell/scripts/yakushi-bar.sh start|stop|toggle|restart` controls the bar.
- Waybar (optional style) uses native MPRIS through `playerctld`; legacy polling scripts are not used.
- CPU and GPU temperatures are read from sysfs/hwmon; the sensors are detected at start-up
  (Waybar's paths are generated into `~/.config/waybar/hardware.local.jsonc`). NVIDIA's
  proprietary driver exposes no hwmon sensor, so the GPU temperature is hidden there.
- Night Light uses `hyprsunset` and restores the last saved state at startup.

## Notes

- Settings always opens on the **System** page.
- The System page includes a clickable persistent image slot; the selected image stays local and is not tracked by Git.

- Desktop notifications are disabled by default; no notification daemon is autostarted.

- Disabled keybinds keep their metadata while releasing the shortcut for another active bind.
- Rofi opacity changes the launcher background alpha.
- Top bar opacity applies to the island and to Waybar's three containers.
- CPU and GPU temperature modules use machine-local stable hwmon parent paths instead of relying on a fixed `hwmonN` number.
- User-specific display connectors are kept out of the repository.

## Credits

These dotfiles are based on and substantially modify [43PR/dotfiles](https://github.com/43PR/dotfiles).

The original project is distributed under the MIT License. Its copyright and license notice are preserved.

## License

MIT. See [`LICENSE`](LICENSE).
