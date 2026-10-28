#!/usr/bin/env python3
"""Spread the Settings accent colour to everything outside Quickshell.

Called by yakushi-uistatectl.py whenever the accent changes (and safe to
run by hand). Each step is independent and best effort:

  * rofi       ~/.config/rofi/accent.rasi (power menu)
  * lock       $accent in ~/.config/hypr/hyprlock.conf
  * windows    border colour, when it follows the accent (yakushi-windowctl)
  * terminal   terminal + fish colours, when matching is on (yakushi-termctl)

Runs once and exits: no daemon, no timers.
"""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

HOME = Path.home()
UI_STATE = HOME / ".config/quickshell/yakushi-ui.local.json"
ROFI_ACCENT = HOME / ".config/rofi/accent.rasi"
WAYBAR_ACCENT = HOME / ".config/waybar/accent.css"
HYPRLOCK = HOME / ".config/hypr/hyprlock.conf"
HELPERS = (
    HOME / ".config/hypr/scripts/yakushi-windowctl.py",
    HOME / ".config/quickshell/scripts/yakushi-termctl.py",
)
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


def accent() -> str:
    try:
        value = json.loads(UI_STATE.read_text()).get("accent")
        if isinstance(value, str) and HEX.match(value):
            return value.lower()
    except (OSError, ValueError, AttributeError):
        pass
    return "#ffffff"


def write_rofi(colour: str) -> None:
    if not ROFI_ACCENT.parent.is_dir():
        return
    ROFI_ACCENT.write_text(
        "/* Written by Yakushi Settings (accent colour). */\n"
        "* {\n"
        f"    accent: {colour}ff;\n"
        f"    accent-soft: {colour}2e;\n"
        "}\n"
    )


def write_waybar(colour: str) -> None:
    """Waybar reloads its style on change (reload_style_on_change)."""
    if not WAYBAR_ACCENT.parent.is_dir():
        return
    WAYBAR_ACCENT.write_text(
        "/* Written by Yakushi Settings (accent colour). */\n"
        f"@define-color accent {colour};\n"
    )


def write_hyprlock(colour: str) -> None:
    try:
        text = HYPRLOCK.read_text()
    except OSError:
        return
    updated = re.sub(r"^\$accent\s*=.*$", f"$accent = rgba({colour[1:]}ff)", text, count=1, flags=re.M)
    if updated != text:
        HYPRLOCK.write_text(updated)


def main() -> None:
    colour = accent()
    write_rofi(colour)
    write_waybar(colour)
    write_hyprlock(colour)
    for helper in HELPERS:
        if helper.exists():
            try:
                subprocess.run(["python3", str(helper), "sync"], capture_output=True, timeout=20)
            except (OSError, subprocess.TimeoutExpired):
                pass
    print(json.dumps({"ok": True, "accent": colour}))


if __name__ == "__main__":
    main()
