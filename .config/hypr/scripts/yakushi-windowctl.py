#!/usr/bin/env python3
"""Window spacing and corners for Settings -> Appearance.

Commands:
    get                         Print the current values as JSON.
    set gaps_out <0..30>        Space between windows and the screen edges.
    set gaps_in <0..20>         Space between neighbouring windows.
    set rounding <0..20>        Corner radius (0 = sharp corners).
    set shadow on|off           Drop shadow around windows.
    set shadow_size <2..40>     Shadow spread in px.
    set border on|off           Coloured border around windows.
    set border_size <1..6>      Border thickness in px.
    set border_color accent|#rrggbb
                                Follow the Settings accent, or a fixed colour.
    sync                        Re-apply after the accent changed.

Gaps and rounding are written into ~/.config/hypr/hyprland.lua. Shadow and
border live in ~/.config/hypr/window.local.lua (machine-local, loaded by
hyprland.lua), with their settings in yakushi-window.local.json. Everything
is applied to the running Hyprland at once, without a reload or flicker.
Runs only when called.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

HYPR = Path.home() / ".config/hypr"
CONFIG = HYPR / "hyprland.lua"
STATE = HYPR / "yakushi-window.local.json"
LOCAL_LUA = HYPR / "window.local.lua"
UI_STATE = Path.home() / ".config/quickshell/yakushi-ui.local.json"

HEX = re.compile(r"^#[0-9a-fA-F]{6}$")

DECOR_DEFAULTS = {
    "shadow": True,
    "shadow_size": 8,
    "border": False,
    "border_size": 2,
    "border_color": "accent",
}

DECOR_LIMITS = {"shadow_size": (2, 40), "border_size": (1, 6)}

SETTINGS = {
    # name: (Lua key, hyprctl keyword, min, max)
    "gaps_out": ("gaps_out", "general:gaps_out", 0, 30),
    "gaps_in": ("gaps_in", "general:gaps_in", 0, 20),
    "rounding": ("rounding", "decoration:rounding", 0, 20),
}


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def fail(message: str) -> None:
    emit({"ok": False, "message": message})
    raise SystemExit(1)


def pattern(lua_key: str) -> re.Pattern:
    # `rounding = 8,` but not `rounding_power = 2,`
    return re.compile(r"(\b" + lua_key + r"\s*=\s*)(\d+)")


def read_values(text: str) -> dict:
    values = {}
    for name, (lua_key, _, _, _) in SETTINGS.items():
        match = pattern(lua_key).search(text)
        if match:
            values[name] = int(match.group(2))
    return values


# ---------------------------------------------------------------------------
# Shadow + border (window.local.lua)
# ---------------------------------------------------------------------------

def load_decor() -> dict:
    state = dict(DECOR_DEFAULTS)
    try:
        saved = json.loads(STATE.read_text())
    except (OSError, ValueError):
        return state

    if isinstance(saved, dict):
        for key in ("shadow", "border"):
            if isinstance(saved.get(key), bool):
                state[key] = saved[key]
        for key, (low, high) in DECOR_LIMITS.items():
            value = saved.get(key)
            if isinstance(value, int) and not isinstance(value, bool):
                state[key] = max(low, min(high, value))
        colour = saved.get("border_color")
        if colour == "accent" or (isinstance(colour, str) and HEX.match(colour)):
            state["border_color"] = colour

    return state


def accent() -> str:
    try:
        value = json.loads(UI_STATE.read_text()).get("accent")
        if isinstance(value, str) and HEX.match(value):
            return value.lower()
    except (OSError, ValueError, AttributeError):
        pass
    return "#ffffff"


def lua_config(state: dict) -> str:
    colour = accent() if state["border_color"] == "accent" else state["border_color"].lower()
    rgb = colour[1:]
    border = state["border_size"] if state["border"] else 0
    return (
        "hl.config({\n"
        "    general = {\n"
        f"        border_size = {border},\n"
        "        col = {\n"
        f'            active_border = "rgba({rgb}ff)",\n'
        f'            inactive_border = "rgba({rgb}40)",\n'
        "        },\n"
        "    },\n"
        "    decoration = {\n"
        "        shadow = {\n"
        f"            enabled = {'true' if state['shadow'] else 'false'},\n"
        f"            range = {state['shadow_size']},\n"
        "        },\n"
        "    },\n"
        "})\n"
    )


def write_decor(state: dict) -> None:
    HYPR.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2) + "\n")
    lua = lua_config(state)
    LOCAL_LUA.write_text(
        "-- Window shadow and border, written by Settings -> Appearance\n"
        "-- (yakushi-windowctl.py). Machine-local; safe to delete.\n" + lua
    )
    apply_decor_live(state, lua)


def apply_decor_live(state: dict, lua: str) -> None:
    """Apply without a reload: one `hyprctl eval`, keywords as a fallback."""
    try:
        proc = subprocess.run(
            ["hyprctl", "eval", lua], capture_output=True, text=True, timeout=5
        )
        out = (proc.stdout + proc.stderr).lower()
        if proc.returncode == 0 and "error" not in out and "unknown" not in out:
            return
    except (OSError, subprocess.TimeoutExpired):
        return  # Not in a Hyprland session: applies at login.

    colour = accent() if state["border_color"] == "accent" else state["border_color"].lower()
    rgb = colour[1:]
    for keyword, value in (
        ("general:border_size", str(state["border_size"] if state["border"] else 0)),
        ("general:col.active_border", f"rgba({rgb}ff)"),
        ("general:col.inactive_border", f"rgba({rgb}40)"),
        ("decoration:shadow:enabled", "true" if state["shadow"] else "false"),
        ("decoration:shadow:range", str(state["shadow_size"])),
    ):
        apply_live(keyword, value)


def set_decor(name: str, raw: str) -> None:
    state = load_decor()

    if name in ("shadow", "border"):
        if raw not in ("on", "off"):
            fail("Expected on or off.")
        state[name] = raw == "on"
    elif name in DECOR_LIMITS:
        low, high = DECOR_LIMITS[name]
        try:
            state[name] = max(low, min(high, int(round(float(raw)))))
        except ValueError:
            fail("Invalid number.")
    elif name == "border_color":
        if raw != "accent" and not HEX.match(raw):
            fail("Colour must be accent or #rrggbb.")
        state[name] = raw.lower()

    write_decor(state)
    emit({"ok": True, **state})


def get() -> None:
    try:
        text = CONFIG.read_text()
    except OSError:
        fail(f"Missing {CONFIG}")
        return

    values = read_values(text)
    missing = [name for name in SETTINGS if name not in values]
    if missing:
        fail("Could not find " + ", ".join(missing) + " in hyprland.lua.")

    emit({"ok": True, **values, **load_decor(), "accent": accent()})


def apply_live(keyword: str, value: int) -> None:
    try:
        subprocess.run(
            ["hyprctl", "keyword", keyword, str(value)],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass  # Not in a Hyprland session: the file change applies at login.


def set_value(name: str, raw: str) -> None:
    if name in DECOR_DEFAULTS:
        set_decor(name, raw)
        return

    if name not in SETTINGS:
        fail(f"Unknown setting: {name}")

    lua_key, keyword, low, high = SETTINGS[name]

    try:
        value = max(low, min(high, int(round(float(raw)))))
    except ValueError:
        fail("Invalid number.")
        return

    try:
        text = CONFIG.read_text()
    except OSError:
        fail(f"Missing {CONFIG}")
        return

    updated, count = pattern(lua_key).subn(lambda m: m.group(1) + str(value), text, count=1)
    if count != 1:
        fail(f"Could not find {lua_key} in hyprland.lua.")

    if updated != text:
        CONFIG.write_text(updated)

    apply_live(keyword, value)
    emit({"ok": True, **read_values(updated)})


def main() -> None:
    args = sys.argv[1:]

    if args == ["get"]:
        get()
    elif len(args) == 3 and args[0] == "set":
        set_value(args[1], args[2])
    elif args == ["sync"]:
        # Only matters when the border follows the accent colour.
        if STATE.exists() and load_decor()["border_color"] == "accent":
            write_decor(load_decor())
        emit({"ok": True})
    else:
        fail("Usage: get | set <name> <value> | sync")


if __name__ == "__main__":
    main()
