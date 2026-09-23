#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if ! command -v pacman >/dev/null 2>&1; then
    echo "ERROR: Yakushi Dotfiles targets Arch Linux and Arch-based systems using pacman." >&2
    exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
    echo "ERROR: sudo is required for automatic installation." >&2
    exit 1
fi

if ! command -v fish >/dev/null 2>&1; then
    echo "Installing Fish bootstrap dependency..."
    sudo pacman -S --needed --noconfirm fish
fi

exec fish "$repo_dir/install.fish"
