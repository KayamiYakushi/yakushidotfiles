# 薬 Dotfiles

A light Hyprland desktop built around one **Settings** panel and an island top bar.
Official Arch repositories only, no AUR, and nothing runs in the background unless it is needed.

<p align="center">
  <img src="assets/preview.png" alt="Desktop preview">
</p>

## Features

- **Settings** (`SUPER + I`) — sharp or rounded style, accent colours, window gaps / corners /
  shadow / border, top bar, login screen, keybinds, default apps, input, sound, monitors,
  network and Bluetooth. Every change applies instantly.
- **Island top bar** — workspaces, RAM, CPU, temperatures, now playing (with a drop-down player
  and visualizer), volume, date, time and a power menu. Modules can be toggled and reordered.
  A plain **Waybar** style in the same look is one click away.
- **One accent everywhere** — bar, power menu, window borders, lock screen and terminal colours
  (kitty, alacritty, foot, ghostty, fish) follow the chosen accent.
- **Default apps** — scans what is installed and sets the terminal, shell, file manager,
  browser, editor and viewers.
- **Wallpaper picker** (`SUPER + W`) — every image under `~/Documents`, applied with `awww`.

## Install

```fish
git clone https://github.com/KayamiYakushi/yakushidotfiles.git
cd yakushidotfiles
sh install.sh
```

The installer installs the packages from the official repositories, backs up your current
configs to `~/YakushiBackups/`, installs the desktop and the SDDM theme, and detects your
keyboard layout. If another login manager is enabled, it is left alone.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| `SUPER + I` | Settings |
| `SUPER + SPACE` | App launcher |
| `SUPER + Q` / `E` / `B` | Terminal / file manager / browser |
| `SUPER + C` | Close window |
| `SUPER + V` | Clipboard history |
| `SUPER + SHIFT + S` | Area screenshot to clipboard |
| `SUPER + W` | Wallpaper picker |
| `SUPER + TAB` | Lock screen |
| ``SUPER + ` `` | Power menu |
| `SUPER + SHIFT + W` | Show / hide the bar |

All of them can be changed in Settings → Keybinds.

## License

MIT — see [`LICENSE`](LICENSE).
