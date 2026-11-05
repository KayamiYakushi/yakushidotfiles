#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import shutil
import sys
from pathlib import Path


def write_safely(path, text: str) -> None:
    """Write a config file in place (same file, so watchers and symlinks keep
    working), but only after a trial copy proved the disk has room for it: on
    a full disk the old file stays whole instead of ending up empty."""
    real = os.path.realpath(path)
    data = text.encode()
    trial = os.path.join(os.path.dirname(real), "." + os.path.basename(real) + ".yakushi-new")
    try:
        with open(trial, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
    finally:
        try:
            os.unlink(trial)
        except OSError:
            pass
    try:
        with open(real, "rb") as f:
            old = f.read()
    except FileNotFoundError:
        old = None
    try:
        with open(real, "r+b" if old is not None else "wb") as f:
            f.write(data)
            f.truncate()
    except OSError:
        if old is not None:                      # put the old one back
            with open(real, "r+b") as f:
                f.write(old)
                f.truncate()
        raise


HOME = Path.home()
CANDIDATES = [
    HOME / ".config/rofi/config.rasi",
]

BACKUP = HOME / ".config/rofi/.yakushi-opacity-last-good.rasi"

HEX8_RE = re.compile(
    r'(?m)^(\s*bg\s*:\s*#)([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})(\s*;)'
)

HEX6_RE = re.compile(
    r'(?m)^(\s*bg\s*:\s*#)([0-9A-Fa-f]{6})(\s*;)'
)

def emit(obj):
    print(json.dumps(obj, ensure_ascii=False))

def fail(message, code=1):
    emit({"ok": False, "message": message})
    raise SystemExit(code)

def find_target():
    for path in CANDIDATES:
        if not path.exists():
            continue

        text = path.read_text()

        if HEX8_RE.search(text) or HEX6_RE.search(text):
            return path, text

    fail("Could not find the Rofi bg color variable.")

def get_opacity():
    path, text = find_target()

    match = HEX8_RE.search(text)

    if match:
        alpha = int(match.group(3), 16) / 255.0
    else:
        alpha = 1.0

    emit({
        "ok": True,
        "opacity": alpha,
        "percent": round(alpha * 100),
        "file": str(path),
    })

def set_opacity(value):
    try:
        value = float(value)
    except ValueError:
        fail("Invalid opacity value.")

    value = max(0.0, min(1.0, value))
    alpha = round(value * 255)
    alpha_hex = f"{alpha:02X}"

    path, text = find_target()
    shutil.copy2(path, BACKUP)

    match = HEX8_RE.search(text)

    if match:
        updated = HEX8_RE.sub(
            lambda m: (
                m.group(1)
                + m.group(2)
                + alpha_hex
                + m.group(4)
            ),
            text,
            count=1,
        )
    else:
        updated = HEX6_RE.sub(
            lambda m: (
                m.group(1)
                + m.group(2)
                + alpha_hex
                + m.group(3)
            ),
            text,
            count=1,
        )

    write_safely(path, updated)

    emit({
        "ok": True,
        "opacity": value,
        "percent": round(value * 100),
        "message": f"App launcher opacity → {round(value * 100)}%",
        "file": str(path),
    })

def restore():
    if not BACKUP.exists():
        fail("No previous Rofi opacity state is available.")

    path, _ = find_target()
    shutil.copy2(BACKUP, path)

    emit({
        "ok": True,
        "message": "Previous app launcher opacity restored.",
    })

def main():
    if len(sys.argv) < 2:
        fail("Usage: get | set <0..1> | restore")

    cmd = sys.argv[1]

    if cmd == "get":
        get_opacity()
    elif cmd == "set" and len(sys.argv) >= 3:
        set_opacity(sys.argv[2])
    elif cmd == "restore":
        restore()
    else:
        fail("Invalid command.")

if __name__ == "__main__":
    main()
