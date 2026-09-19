#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
STYLE = HOME / ".config/waybar/style.css"
CONFIG = HOME / ".config/waybar/config.jsonc"
BACKUP_STYLE = HOME / ".config/waybar/.yakushi-opacity-last-good.css"

SECTION_NAMES = [
    ".modules-left",
    ".modules-center",
    ".modules-right",
]

RGBA_RE = re.compile(
    r'background-color\s*:\s*rgba\(\s*'
    r'(?P<r>\d+)\s*,\s*'
    r'(?P<g>\d+)\s*,\s*'
    r'(?P<b>\d+)\s*,\s*'
    r'(?P<a>\d*\.?\d+)\s*\)\s*;'
)

def emit(obj):
    print(json.dumps(obj, ensure_ascii=False))

def fail(message, code=1):
    emit({"ok": False, "message": message})
    raise SystemExit(code)

def find_section(text, selector):
    start = text.find(selector)

    if start == -1:
        fail(f"Could not find {selector} in Waybar CSS.")

    brace = text.find("{", start)
    end = text.find("}", brace)

    if brace == -1 or end == -1:
        fail(f"Malformed Waybar CSS near {selector}.")

    return brace, end

def read_opacity():
    if not STYLE.exists():
        fail(f"Missing {STYLE}")

    text = STYLE.read_text()
    values = []

    for selector in SECTION_NAMES:
        brace, end = find_section(text, selector)
        match = RGBA_RE.search(text[brace + 1:end])

        if not match:
            fail(f"Could not find rgba background in {selector}.")

        values.append(float(match.group("a")))

    value = sum(values) / len(values)

    emit({
        "ok": True,
        "opacity": value,
        "percent": round(value * 100),
        "file": str(STYLE),
    })

def replace_opacity(text, selector, value):
    brace, end = find_section(text, selector)
    body = text[brace + 1:end]
    match = RGBA_RE.search(body)

    if not match:
        fail(f"Could not find rgba background in {selector}.")

    alpha = f"{value:.3f}".rstrip("0").rstrip(".")

    replacement = (
        "background-color: rgba("
        + match.group("r") + ", "
        + match.group("g") + ", "
        + match.group("b") + ", "
        + alpha
        + ");"
    )

    new_body = body[:match.start()] + replacement + body[match.end():]
    return text[:brace + 1] + new_body + text[end:]

def ensure_reload_style_flag():
    if not CONFIG.exists():
        return

    text = CONFIG.read_text()

    if '"reload_style_on_change"' in text:
        return

    stripped = text.lstrip()

    if not stripped.startswith("{"):
        return

    leading = len(text) - len(stripped)
    brace = leading + stripped.find("{")

    text = (
        text[:brace + 1]
        + '\n    "reload_style_on_change": true,'
        + text[brace + 1:]
    )

    CONFIG.write_text(text)

def reload_waybar():
    proc = subprocess.run(
        ["pgrep", "-x", "waybar"],
        text=True,
        capture_output=True,
    )

    if proc.returncode != 0:
        return False, "Waybar is not running."

    pids = [
        int(line.strip())
        for line in proc.stdout.splitlines()
        if line.strip().isdigit()
    ]

    for pid in pids:
        try:
            os.kill(pid, signal.SIGUSR2)
        except ProcessLookupError:
            pass

    time.sleep(0.08)
    return True, "Waybar reloaded."

def set_opacity(value):
    try:
        value = float(value)
    except ValueError:
        fail("Invalid opacity value.")

    value = max(0.0, min(1.0, value))

    if not STYLE.exists():
        fail(f"Missing {STYLE}")

    text = STYLE.read_text()
    shutil.copy2(STYLE, BACKUP_STYLE)

    for selector in SECTION_NAMES:
        text = replace_opacity(text, selector, value)

    STYLE.write_text(text)
    ensure_reload_style_flag()
    reload_waybar()

    emit({
        "ok": True,
        "opacity": value,
        "percent": round(value * 100),
        "message": f"Top bar opacity → {round(value * 100)}%",
    })

def restore():
    if not BACKUP_STYLE.exists():
        fail("No previous Waybar opacity state is available.")

    shutil.copy2(BACKUP_STYLE, STYLE)
    reload_waybar()

    emit({
        "ok": True,
        "message": "Previous top bar opacity restored.",
    })

def main():
    if len(sys.argv) < 2:
        fail("Usage: get | set <0..1> | restore")

    cmd = sys.argv[1]

    if cmd == "get":
        read_opacity()
    elif cmd == "set" and len(sys.argv) >= 3:
        set_opacity(sys.argv[2])
    elif cmd == "restore":
        restore()
    else:
        fail("Invalid command.")

if __name__ == "__main__":
    main()
