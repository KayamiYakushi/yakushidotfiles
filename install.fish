#!/usr/bin/env fish

set -l repo (cd (dirname (status --current-filename)); and pwd)
set -l stamp (date +%Y-%m-%d_%H-%M-%S)
set -l backup "$HOME/YakushiBackups/install-$stamp"

echo "Yakushi Dotfiles installer"
echo "Repository: $repo"
echo "Backup: $backup"
echo

mkdir -p "$backup" "$HOME/.config"

set -l managed hypr quickshell waybar rofi

for name in $managed
    set -l src "$repo/.config/$name"
    set -l dst "$HOME/.config/$name"

    if not test -d "$src"
        echo "Missing repository directory: $src"
        exit 1
    end

    if test -e "$dst"; or test -L "$dst"
        echo "Backing up ~/.config/$name"
        cp -a "$dst" "$backup/$name"
    end
end

echo
echo "Installing managed configuration..."

for name in $managed
    set -l src "$repo/.config/$name"
    set -l dst "$HOME/.config/$name"

    rm -rf "$dst"
    cp -a "$src" "$dst"
end

# Never inherit the publisher's monitor topology.
rm -f "$HOME/.config/hypr/monitors.local.lua"
rm -f "$HOME/.config/hypr/yakushi-monitor-state.local.json"

mkdir -p "$HOME/.cache/quickshell/wallpaper-index"
mkdir -p "$HOME/.cache/quickshell/thumbs"

# Detect stable hwmon paths once; Waybar reads sysfs natively at runtime.
python3 "$HOME/.config/waybar/scripts/generate-hardware-local.py"

echo
echo "Checking commands..."

set -l required \
    hyprctl qs waybar rofi python3 kitty thunar \
    wl-copy cliphist grim slurp brightnessctl hyprsunset \
    playerctl pavucontrol wlogout awww jq

set -l missing

for cmd in $required
    if not command -q $cmd
        set -a missing $cmd
    end
end

if not command -q magick; and not command -q convert
    set -a missing imagemagick
end

if test (count $missing) -gt 0
    echo "Missing commands/packages:"
    for cmd in $missing
        echo "  - $cmd"
    end
    echo
    echo "Install the missing runtime dependencies before using all features."
else
    echo "Required commands found."
end

echo
echo "Reloading Hyprland..."
hyprctl reload 2>/dev/null

echo "Restarting Waybar..."
pkill waybar 2>/dev/null
sleep 0.25
waybar >/tmp/yakushi-waybar-install.log 2>&1 &
disown

echo
echo "Yakushi Dotfiles installed."
echo "Backup: $backup"
echo "Wallpaper source: ~/Documents (recursive)"
echo "Yakushi Settings: SUPER + I"
echo "Wallpaper selector: SUPER + W"
