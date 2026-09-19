#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
CONFIG = HOME / ".config/hypr/hyprland.lua"
BACKUP = HOME / ".config/hypr/hyprland.lua.yakushi-input-last-good"

LAYOUT_RE = re.compile(r'(\bkb_layout\s*=\s*)"([^"]*)"')
SENS_RE = re.compile(r'(\bsensitivity\s*=\s*)(-?\d+(?:\.\d+)?)')

XKB_RULES = [
    Path("/usr/share/X11/xkb/rules/evdev.lst"),
    Path("/usr/share/X11/xkb/rules/base.lst"),
]

def emit(obj):
    print(json.dumps(obj, ensure_ascii=False))

def fail(message, code=1):
    emit({"ok": False, "message": message})
    raise SystemExit(code)

def get_layouts():
    path = next((p for p in XKB_RULES if p.exists()), None)
    if path is None:
        fail("XKB layout catalog was not found.")

    layouts = []
    in_layouts = False

    for raw in path.read_text(errors="replace").splitlines():
        line = raw.rstrip()

        if line.startswith("!"):
            in_layouts = line.strip().startswith("! layout")
            continue

        if not in_layouts or not line.strip():
            continue

        parts = line.strip().split(None, 1)
        if not parts:
            continue

        code = parts[0]
        name = parts[1] if len(parts) > 1 else code

        layouts.append({
            "code": code,
            "name": name,
        })

    seen = set()
    unique = []

    for item in layouts:
        if item["code"] in seen:
            continue
        seen.add(item["code"])
        unique.append(item)

    return unique

def read_state():
    if not CONFIG.exists():
        fail(f"Missing {CONFIG}")

    text = CONFIG.read_text()
    lm = LAYOUT_RE.search(text)
    sm = SENS_RE.search(text)

    if not lm or not sm:
        fail("Could not find input settings in hyprland.lua.")

    return {
        "layout": lm.group(2),
        "sensitivity": float(sm.group(2)),
    }

def reload_hypr():
    proc = subprocess.run(
        ["hyprctl", "reload"],
        text=True,
        capture_output=True,
    )
    output = (proc.stdout + proc.stderr).strip()
    return proc.returncode == 0 and "ok" in output.lower(), output

def patch(pattern, replacement, label):
    text = CONFIG.read_text()
    updated, count = pattern.subn(replacement, text, count=1)

    if count != 1:
        fail(f"Could not update {label}; no changes made.")

    shutil.copy2(CONFIG, BACKUP)
    CONFIG.write_text(updated)

    ok, output = reload_hypr()
    if not ok:
        shutil.copy2(BACKUP, CONFIG)
        reload_hypr()
        fail(
            f"Hyprland rejected {label}; previous config restored. "
            + output
        )

def set_layout(layout):
    layout = layout.strip()

    available = {item["code"] for item in get_layouts()}
    requested = [x.strip() for x in layout.split(",") if x.strip()]

    if not requested or any(x not in available for x in requested):
        fail("That layout is not present in the installed XKB catalog.")

    rendered = ",".join(requested)

    patch(
        LAYOUT_RE,
        lambda m: m.group(1) + '"' + rendered + '"',
        "keyboard layout",
    )

    emit({
        "ok": True,
        "message": f"Keyboard layout → {rendered.upper()}",
        "layout": rendered,
    })

def set_sensitivity(value):
    try:
        value = max(-1.0, min(1.0, float(value)))
    except ValueError:
        fail("Invalid pointer speed.")

    rendered = f"{value:.2f}"

    patch(
        SENS_RE,
        lambda m: m.group(1) + rendered,
        "pointer speed",
    )

    emit({
        "ok": True,
        "message": f"Pointer speed → {rendered}",
        "sensitivity": value,
    })

def runtime_sensitivity(value):
    try:
        value = max(-1.0, min(1.0, float(value)))
    except ValueError:
        fail("Invalid pointer speed.")

    proc = subprocess.run(
        ["hyprctl", "keyword", "input:sensitivity", f"{value:.3f}"],
        text=True,
        capture_output=True,
    )

    if proc.returncode != 0:
        fail(
            (proc.stdout + proc.stderr).strip()
            or "Runtime pointer update failed."
        )

    emit({"ok": True, "sensitivity": value})

def restore():
    if not BACKUP.exists():
        fail("No previous Input state is available.")

    current = CONFIG.with_suffix(".lua.yakushi-before-input-restore")
    shutil.copy2(CONFIG, current)
    shutil.copy2(BACKUP, CONFIG)

    ok, output = reload_hypr()
    if not ok:
        shutil.copy2(current, CONFIG)
        reload_hypr()
        fail("Restore failed; current config was kept. " + output)

    emit({"ok": True, "message": "Restored previous Input settings."})

def main():
    if len(sys.argv) < 2:
        fail("Usage: get | layouts | set-layout <code> | set-sensitivity <value> | runtime-sensitivity <value> | restore")

    cmd = sys.argv[1]

    if cmd == "get":
        state = read_state()
        state["ok"] = True
        emit(state)
    elif cmd == "layouts":
        emit(get_layouts())
    elif cmd == "set-layout" and len(sys.argv) >= 3:
        set_layout(sys.argv[2])
    elif cmd == "set-sensitivity" and len(sys.argv) >= 3:
        set_sensitivity(sys.argv[2])
    elif cmd == "runtime-sensitivity" and len(sys.argv) >= 3:
        runtime_sensitivity(sys.argv[2])
    elif cmd == "restore":
        restore()
    else:
        fail("Invalid command.")

if __name__ == "__main__":
    main()
