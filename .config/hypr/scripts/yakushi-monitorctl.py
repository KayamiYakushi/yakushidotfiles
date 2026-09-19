#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
MONITORS_LUA = HOME / ".config/hypr/monitors.local.lua"
STATE_FILE = HOME / ".config/hypr/yakushi-monitor-state.local.json"
LAST_GOOD_LUA = HOME / ".config/hypr/monitors.local.lua.yakushi-last-good"
LAST_GOOD_STATE = HOME / ".config/hypr/yakushi-monitor-state.local.json.yakushi-last-good"

BEGIN = "-- YAKUSHI_MONITORS_BEGIN"
END = "-- YAKUSHI_MONITORS_END"

MODE_RE = re.compile(
    r"^(?P<w>\d+)x(?P<h>\d+)@(?P<hz>\d+(?:\.\d+)?)(?:Hz)?$"
)

def emit(obj):
    print(json.dumps(obj, ensure_ascii=False))

def fail(message, code=1):
    emit({"ok": False, "message": message})
    raise SystemExit(code)

def run(args):
    return subprocess.run(args, text=True, capture_output=True)

def hypr_monitors():
    proc = run(["hyprctl", "-j", "monitors", "all"])

    if proc.returncode != 0:
        fail((proc.stdout + proc.stderr).strip() or "Could not query monitors.")

    try:
        return json.loads(proc.stdout)
    except Exception as exc:
        fail(f"Could not parse monitor data: {exc}")

def parsed_modes(mon):
    result = []

    for raw in mon.get("availableModes", []) or []:
        match = MODE_RE.match(str(raw).strip())
        if not match:
            continue

        result.append({
            "raw": str(raw),
            "width": int(match.group("w")),
            "height": int(match.group("h")),
            "refresh": float(match.group("hz")),
        })

    current = {
        "raw": (
            f"{int(mon.get('width', 0))}x{int(mon.get('height', 0))}"
            f"@{float(mon.get('refreshRate', 0)):.5f}Hz"
        ),
        "width": int(mon.get("width", 0)),
        "height": int(mon.get("height", 0)),
        "refresh": float(mon.get("refreshRate", 0)),
    }

    if current["width"] > 0 and current["height"] > 0:
        if not any(
            m["width"] == current["width"]
            and m["height"] == current["height"]
            and abs(m["refresh"] - current["refresh"]) < 0.05
            for m in result
        ):
            result.append(current)

    return result

def grouped_resolutions(mon):
    groups = {}

    for mode in parsed_modes(mon):
        key = (mode["width"], mode["height"])
        groups.setdefault(key, []).append(mode["refresh"])

    items = []

    for (width, height), rates in groups.items():
        items.append({
            "width": width,
            "height": height,
            "label": f"{width}×{height}",
            "refreshRates": sorted(
                {round(float(rate), 3) for rate in rates},
                reverse=True,
            ),
        })

    items.sort(
        key=lambda item: (
            item["width"] * item["height"],
            item["width"],
            item["height"],
        ),
        reverse=True,
    )

    return items

def enriched_monitors():
    result = []

    for mon in hypr_monitors():
        scale = float(mon.get("scale", 1.0)) or 1.0
        width = int(mon.get("width", 0))
        height = int(mon.get("height", 0))

        result.append({
            "id": mon.get("id"),
            "name": mon.get("name", ""),
            "description": mon.get("description", ""),
            "make": mon.get("make", ""),
            "model": mon.get("model", ""),
            "serial": mon.get("serial", ""),
            "width": width,
            "height": height,
            "logicalWidth": width / scale,
            "logicalHeight": height / scale,
            "refreshRate": float(mon.get("refreshRate", 0)),
            "x": int(mon.get("x", 0)),
            "y": int(mon.get("y", 0)),
            "scale": scale,
            "focused": bool(mon.get("focused", False)),
            "disabled": bool(mon.get("disabled", False)),
            "resolutions": grouped_resolutions(mon),
        })

    result.sort(key=lambda x: (x["x"], x["y"], x["name"]))
    return result

def get_monitor(name):
    for mon in hypr_monitors():
        if mon.get("name") == name:
            return mon
    return None

def find_mode(mon, width, height, refresh):
    candidates = [
        mode for mode in parsed_modes(mon)
        if mode["width"] == width and mode["height"] == height
    ]

    if not candidates:
        return None

    return min(
        candidates,
        key=lambda mode: abs(mode["refresh"] - refresh),
    )

def current_mode_string(mon):
    mode = find_mode(
        mon,
        int(mon.get("width", 0)),
        int(mon.get("height", 0)),
        float(mon.get("refreshRate", 0)),
    )

    if mode is not None:
        raw = mode["raw"].strip()
        return raw[:-2] if raw.lower().endswith("hz") else raw

    return (
        f"{int(mon.get('width', 0))}x{int(mon.get('height', 0))}"
        f"@{float(mon.get('refreshRate', 0)):.3f}"
    )

def lua_quote(value):
    return json.dumps(str(value), ensure_ascii=False)

def runtime_apply(name, mode, x, y, scale):
    lua = (
        "hl.monitor({ "
        f"output = {lua_quote(name)}, "
        f"mode = {lua_quote(mode)}, "
        f"position = {lua_quote(f'{int(x)}x{int(y)}')}, "
        f"scale = {float(scale):.3f} "
        "})"
    )

    proc = run(["hyprctl", "eval", lua])
    output = (proc.stdout + proc.stderr).strip()

    if proc.returncode != 0 or "error" in output.lower():
        fail(output or "Hyprland rejected the monitor setting.")

def load_state():
    if not STATE_FILE.exists():
        return {}

    try:
        data = json.loads(STATE_FILE.read_text())
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def save_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(
        json.dumps(state, indent=2, ensure_ascii=False) + "\n"
    )

def snapshot():
    if MONITORS_LUA.exists():
        shutil.copy2(MONITORS_LUA, LAST_GOOD_LUA)

    if STATE_FILE.exists():
        shutil.copy2(STATE_FILE, LAST_GOOD_STATE)
    elif LAST_GOOD_STATE.exists():
        LAST_GOOD_STATE.unlink()

def restore_files():
    if LAST_GOOD_LUA.exists():
        shutil.copy2(LAST_GOOD_LUA, MONITORS_LUA)

    if LAST_GOOD_STATE.exists():
        shutil.copy2(LAST_GOOD_STATE, STATE_FILE)
    elif STATE_FILE.exists():
        STATE_FILE.unlink()

def render_managed_block(state):
    lines = [BEGIN]

    for name in sorted(state):
        cfg = state[name]
        lines.append(
            "hl.monitor({ "
            f"output = {lua_quote(name)}, "
            f"mode = {lua_quote(cfg['mode'])}, "
            f"position = {lua_quote(cfg['position'])}, "
            f"scale = {float(cfg['scale']):.3f} "
            "})"
        )

    lines.append(END)
    return "\n".join(lines)

def write_managed_block(state):
    if MONITORS_LUA.exists():
        text = MONITORS_LUA.read_text()
    else:
        text = "-- Machine-local monitor state. Do not publish this file.\n"

    pattern = re.compile(
        re.escape(BEGIN) + r".*?" + re.escape(END),
        flags=re.S,
    )

    block = render_managed_block(state)

    if pattern.search(text):
        text = pattern.sub(block, text)
    else:
        text = text.rstrip() + "\n\n" + block + "\n"

    MONITORS_LUA.write_text(text)

def validate_reload():
    proc = run(["hyprctl", "reload"])
    output = (proc.stdout + proc.stderr).strip()

    if proc.returncode != 0 or "error" in output.lower():
        return False, output

    errors = run(["hyprctl", "configerrors"])
    error_text = (errors.stdout + errors.stderr).strip()

    if error_text and error_text.lower() not in {"no errors", "none"}:
        return False, error_text

    return True, output

def persist(name, mode, x, y, scale):
    state = load_state()
    state[name] = {
        "mode": mode,
        "position": f"{int(x)}x{int(y)}",
        "scale": float(scale),
    }
    save_state(state)
    write_managed_block(state)

def apply_mode(name, width, height, refresh):
    mon = get_monitor(name)

    if mon is None:
        fail(f"Monitor not found: {name}")

    mode = find_mode(mon, width, height, refresh)

    if mode is None:
        fail(f"{width}x{height}@{refresh:.2f} is not exposed by {name}.")

    raw = mode["raw"].strip()
    mode_string = raw[:-2] if raw.lower().endswith("hz") else raw

    x = int(mon.get("x", 0))
    y = int(mon.get("y", 0))
    scale = float(mon.get("scale", 1.0))

    snapshot()
    runtime_apply(name, mode_string, x, y, scale)
    time.sleep(0.20)
    persist(name, mode_string, x, y, scale)

    ok, message = validate_reload()
    if not ok:
        restore_files()
        validate_reload()
        fail("Persistence failed and was rolled back. " + message)

    emit({
        "ok": True,
        "message": f"{name} → {mode['width']}×{mode['height']} @ {mode['refresh']:.2f} Hz",
    })

def set_scale(name, scale):
    mon = get_monitor(name)

    if mon is None:
        fail(f"Monitor not found: {name}")

    scale = max(0.5, min(2.0, float(scale)))
    mode = current_mode_string(mon)
    x = int(mon.get("x", 0))
    y = int(mon.get("y", 0))

    snapshot()
    runtime_apply(name, mode, x, y, scale)
    time.sleep(0.20)
    persist(name, mode, x, y, scale)

    ok, message = validate_reload()
    if not ok:
        restore_files()
        validate_reload()
        fail("Scale persistence failed and was rolled back. " + message)

    emit({
        "ok": True,
        "message": f"{name} scale → {scale:.2f}×",
    })

def set_position(name, x, y):
    mon = get_monitor(name)

    if mon is None:
        fail(f"Monitor not found: {name}")

    x = int(x)
    y = int(y)
    mode = current_mode_string(mon)
    scale = float(mon.get("scale", 1.0))

    snapshot()
    runtime_apply(name, mode, x, y, scale)
    time.sleep(0.20)
    persist(name, mode, x, y, scale)

    ok, message = validate_reload()
    if not ok:
        restore_files()
        validate_reload()
        fail("Position persistence failed and was rolled back. " + message)

    emit({
        "ok": True,
        "message": f"{name} position → X {x}, Y {y}",
        "x": x,
        "y": y,
    })

def restore():
    if not LAST_GOOD_LUA.exists():
        fail("No previous monitor state is available.")

    restore_files()
    ok, message = validate_reload()

    if not ok:
        fail("Could not restore previous monitor configuration. " + message)

    emit({
        "ok": True,
        "message": "Previous monitor configuration restored.",
    })

def main():
    if len(sys.argv) < 2:
        fail("Usage: list | apply-mode <name> <w> <h> <hz> | set-scale <name> <scale> | set-position <name> <x> <y> | restore")

    cmd = sys.argv[1]

    if cmd == "list":
        emit({"ok": True, "monitors": enriched_monitors()})
    elif cmd == "apply-mode" and len(sys.argv) >= 6:
        apply_mode(
            sys.argv[2],
            int(sys.argv[3]),
            int(sys.argv[4]),
            float(sys.argv[5]),
        )
    elif cmd == "set-scale" and len(sys.argv) >= 4:
        set_scale(sys.argv[2], float(sys.argv[3]))
    elif cmd == "set-position" and len(sys.argv) >= 5:
        set_position(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
    elif cmd == "restore":
        restore()
    else:
        fail("Invalid command.")

if __name__ == "__main__":
    main()
