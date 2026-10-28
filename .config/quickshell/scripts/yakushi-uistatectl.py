#!/usr/bin/env python3
"""Persist Settings appearance state (panel opacity, accent colour, style).

Commands:
    get                               Print the saved state as JSON.
    set <opacity> <#rrggbb> [style]   Save the state (style: sharp|rounded).

State lives in ~/.config/quickshell/yakushi-ui.local.json (machine-local,
git-ignored). If it does not exist yet, a legacy
yakushi-panel-opacity.local.json is read once so older saves are not lost.

Runs only when called: no daemon, no timers.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

DIR = Path.home() / ".config/quickshell"
STATE = DIR / "yakushi-ui.local.json"
LEGACY = DIR / "yakushi-panel-opacity.local.json"

OPACITY_MIN = 0.40
OPACITY_MAX = 1.00
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def clamp(value: float) -> float:
    return max(OPACITY_MIN, min(OPACITY_MAX, value))


def number_from_legacy(data) -> float | None:
    """Best-effort: find a plausible opacity in whatever the old script wrote."""
    if isinstance(data, (int, float)) and not isinstance(data, bool):
        return float(data)

    if isinstance(data, dict):
        for key in ("panelOpacity", "panel_opacity", "opacity", "value"):
            value = data.get(key)
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                return float(value)

        for value in data.values():
            found = number_from_legacy(value)
            if found is not None:
                return found

    return None


def read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def get() -> None:
    result: dict = {"ok": True}

    state = read_json(STATE)
    if isinstance(state, dict):
        opacity = state.get("panelOpacity")
        accent = state.get("accent")

        if isinstance(opacity, (int, float)) and not isinstance(opacity, bool):
            result["panelOpacity"] = clamp(float(opacity))

        if isinstance(accent, str) and HEX.match(accent):
            result["accent"] = accent.lower()

        if state.get("style") in ("sharp", "rounded"):
            result["style"] = state["style"]

    elif LEGACY.exists():
        legacy = number_from_legacy(read_json(LEGACY))
        if legacy is not None and 0.0 <= legacy <= 1.0:
            result["panelOpacity"] = clamp(legacy)

    emit(result)


def set_state(opacity_raw: str, accent: str, style: str | None = None) -> None:
    try:
        opacity = clamp(float(opacity_raw))
    except ValueError:
        emit({"ok": False, "message": "Invalid opacity."})
        raise SystemExit(1)

    if not HEX.match(accent):
        emit({"ok": False, "message": "Invalid accent colour."})
        raise SystemExit(1)

    DIR.mkdir(parents=True, exist_ok=True)

    # Keep keys this command does not set (e.g. the style).
    previous = read_json(STATE)
    data = previous if isinstance(previous, dict) else {}
    data["panelOpacity"] = round(opacity, 3)
    data["accent"] = accent.lower()
    if style in ("sharp", "rounded"):
        data["style"] = style

    payload = json.dumps(data, indent=2) + "\n"

    fd, tmp = tempfile.mkstemp(dir=str(DIR), prefix=".ui-state-")
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(payload)
        os.replace(tmp, STATE)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

    # Let the island top bar, the launcher, window borders and the terminal
    # follow the new accent (best effort, neither blocks).
    for args in (
        ["qs", "-p", str(DIR / "topbar-shell.qml"), "ipc", "call", "topbar", "reload"],
        ["python3", str(DIR / "scripts/yakushi-themesync.py")],
    ):
        try:
            subprocess.Popen(
                args,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError:
            pass

    emit({"ok": True})


def main() -> None:
    args = sys.argv[1:]

    if args[:1] == ["get"]:
        get()
    elif args[:1] == ["set"] and len(args) in (3, 4):
        set_state(args[1], args[2], args[3] if len(args) == 4 else None)
    else:
        emit({"ok": False, "message": "Usage: get | set <opacity> <#rrggbb> [sharp|rounded]"})
        raise SystemExit(1)


if __name__ == "__main__":
    main()
