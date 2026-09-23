#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "This installer must run as root." >&2
    exit 1
fi

repo_sddm_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

install -d -m 0755 /usr/share/sddm/themes/yakushi
install -m 0644 "$repo_sddm_dir/yakushi/Main.qml" \
    /usr/share/sddm/themes/yakushi/Main.qml
install -m 0644 "$repo_sddm_dir/yakushi/theme.conf" \
    /usr/share/sddm/themes/yakushi/theme.conf
install -m 0644 "$repo_sddm_dir/yakushi/metadata.desktop" \
    /usr/share/sddm/themes/yakushi/metadata.desktop

install -d -m 0755 /usr/local/libexec
install -m 0755 "$repo_sddm_dir/yakushi-sddmctl-root" \
    /usr/local/libexec/yakushi-sddmctl

install -d -m 0755 /etc/sddm.conf.d
install -m 0644 "$repo_sddm_dir/99-yakushi-theme.conf" \
    /etc/sddm.conf.d/99-yakushi-theme.conf

echo "Yakushi SDDM system files installed."
