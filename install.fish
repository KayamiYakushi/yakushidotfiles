#!/usr/bin/env fish

set -l repo (cd (dirname (status --current-filename)); and pwd)
set -l stamp (date +%Y-%m-%d_%H-%M-%S)
set -l backup "$HOME/YakushiBackups/install-$stamp"

echo "Yakushi Dotfiles v1.0.0 installer"
echo "Repository: $repo"
echo "Backup: $backup"
echo

if not command -q pacman
    echo "ERROR: This installer targets Arch Linux and Arch-based systems using pacman."
    exit 1
end

if not command -q sudo
    echo "ERROR: sudo is required for package and system-file installation."
    exit 1
end

# Official Arch repository dependencies only. No AUR helper is required.
set -l packages \
    fish \
    hyprland \
    quickshell \
    waybar \
    rofi \
    python \
    kitty \
    nautilus \
    firefox \
    networkmanager \
    wl-clipboard \
    cliphist \
    grim \
    slurp \
    brightnessctl \
    hyprsunset \
    hyprlock \
    playerctl \
    pavucontrol \
    awww \
    jq \
    imagemagick \
    qt6-imageformats \
    qt6ct \
    hyprpolkitagent \
    hyprtoolkit \
    xdg-desktop-portal-hyprland \
    sddm \
    bluez \
    bluez-utils \
    pipewire \
    pipewire-pulse \
    wireplumber \
    noto-fonts \
    noto-fonts-cjk \
    ttf-jetbrains-mono-nerd

echo "Installing required official-repository packages..."
sudo -v
or begin
    echo "ERROR: sudo authentication failed."
    exit 1
end

sudo pacman -S --needed --noconfirm $packages
or begin
    echo "ERROR: Dependency installation failed."
    exit 1
end

mkdir -p "$backup" "$HOME/.config"

set -l managed hypr quickshell waybar rofi hyprpolkitagent qt6ct

for name in $managed
    set -l src "$repo/.config/$name"
    set -l dst "$HOME/.config/$name"

    if not test -d "$src"
        echo "ERROR: Missing repository directory: $src"
        exit 1
    end

    if test -e "$dst"; or test -L "$dst"
        echo "Backing up ~/.config/$name"
        cp -a "$dst" "$backup/$name"
    end
end

set -l systemd_src "$repo/.config/systemd/user/hyprpolkitagent.service.d"
set -l systemd_dst "$HOME/.config/systemd/user/hyprpolkitagent.service.d"

if not test -d "$systemd_src"
    echo "ERROR: Missing systemd override: $systemd_src"
    exit 1
end

if test -d "$systemd_dst"
    mkdir -p "$backup/systemd-user"
    cp -a "$systemd_dst" "$backup/systemd-user/"
end

echo
echo "Installing managed configuration..."

for name in $managed
    set -l src "$repo/.config/$name"
    set -l dst "$HOME/.config/$name"

    rm -rf "$dst"
    cp -a "$src" "$dst"
end

mkdir -p (dirname "$systemd_dst")
rm -rf "$systemd_dst"
cp -a "$systemd_src" "$systemd_dst"

# Materialize the user-specific qt6ct config from the portable template.
set -l qt_template "$HOME/.config/qt6ct/qt6ct.conf.template"
if test -f "$qt_template"
    string replace -a '@HOME@' "$HOME" < "$qt_template" \
        > "$HOME/.config/qt6ct/qt6ct.conf"
end

# Never inherit the publisher's monitor topology.
rm -f "$HOME/.config/hypr/monitors.local.lua"
rm -f "$HOME/.config/hypr/yakushi-monitor-state.local.json"

mkdir -p "$HOME/Documents" "$HOME/Downloads" "$HOME/Pictures"
mkdir -p "$HOME/.cache/quickshell/wallpaper-index"
mkdir -p "$HOME/.cache/quickshell/thumbs"

# Detect stable hwmon paths once; Waybar reads sysfs natively at runtime.
python3 "$HOME/.config/waybar/scripts/generate-hardware-local.py"
or begin
    echo "ERROR: Hardware sensor configuration generation failed."
    exit 1
end

echo
echo "Installing Yakushi SDDM system files..."
sudo sh "$repo/sddm/install-system.sh"
or begin
    echo "ERROR: SDDM theme installation failed."
    exit 1
end

echo
echo "Enabling required services..."
sudo systemctl enable --now NetworkManager.service
sudo systemctl enable --now bluetooth.service

# Enable SDDM for the next boot. Do not start it inside the current desktop session.
sudo systemctl enable sddm.service

systemctl --user daemon-reload
systemctl --user enable --now hyprpolkitagent.service 2>/dev/null
or systemctl --user restart hyprpolkitagent.service 2>/dev/null
or true

echo
echo "Verifying runtime commands..."

set -l required \
    hyprctl \
    qs \
    waybar \
    rofi \
    python3 \
    kitty \
    nautilus \
    firefox \
    nmcli \
    wl-copy \
    cliphist \
    grim \
    slurp \
    brightnessctl \
    hyprsunset \
    hyprlock \
    playerctl \
    pavucontrol \
    awww \
    jq \
    magick \
    bluetoothctl

set -l missing

for cmd in $required
    if not command -q $cmd
        set -a missing $cmd
    end
end

if test (count $missing) -gt 0
    echo "ERROR: Required commands are still missing:"
    for cmd in $missing
        echo "  - $cmd"
    end
    exit 1
end

if set -q HYPRLAND_INSTANCE_SIGNATURE
    echo
    echo "Reloading Hyprland..."
    hyprctl reload 2>/dev/null; or true

    echo "Restarting Waybar..."
    pkill waybar 2>/dev/null; or true
    sleep 0.25
    waybar >/tmp/yakushi-waybar-install.log 2>&1 &
    disown
else
    echo
    echo "No active Hyprland session detected."
    echo "The new configuration will load on the next Hyprland login."
end

echo
echo "Yakushi Dotfiles v1.0.0 installed successfully."
echo "Backup: $backup"
echo "Yakushi Settings: SUPER + I"
echo "Wallpaper selector: SUPER + W"
echo "Power menu: SUPER + GRAVE"
echo
echo "SDDM is enabled for the next boot."
