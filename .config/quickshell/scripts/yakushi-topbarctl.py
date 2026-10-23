#!/usr/bin/env python3
"""Settings backend for the Yakushi top bar.

Commands:
    get                     Print the bar settings as JSON.
    set <key> <value>       Change one setting.
                              style        island | waybar
                              seconds      on | off
                              clock24      on | off
                              opacity      0.40 .. 1.00
                              visualizer   hover | always | off
                              order        comma-separated module ids
                              module.<id>  on | off
    sensors                 Print the CPU/GPU temperature files as JSON.
    init                    Write the defaults if no settings file exists.

Settings live in ~/.config/quickshell/yakushi-topbar.local.json
(machine-local, git-ignored). The island bar watches that file with inotify,
so changes apply instantly without polling or restarts.

"seconds" and "opacity" are shared with Waybar, so the choice survives a
style switch. Runs only when called: no daemon, no timers.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HOME = Path.home()
DIR = HOME / ".config/quickshell"
STATE = DIR / "yakushi-topbar.local.json"
BAR_SCRIPT = DIR / "scripts/yakushi-bar.sh"
ISLAND_QML = DIR / "topbar-shell.qml"
CLOCK_HELPER = HOME / ".config/hypr/scripts/yakushi-clockctl.py"
WAYBAR_OPACITY_HELPER = HOME / ".config/hypr/scripts/yakushi-waybar-opacityctl.py"

MODULES = (
    "workspaces",
    "ram",
    "cpu",
    "cpuTemp",
    "gpuTemp",
    "media",
    "volume",
    "date",
    "time",
    "power",
)

# Default left-to-right order on the island
DEFAULT_ORDER = [
    "workspaces",
    "ram",
    "cpu",
    "cpuTemp",
    "gpuTemp",
    "date",
    "time",
    "media",
    "volume",
    "power",
]

VISUALIZER_MODES = ("hover", "always", "off")

DEFAULTS: dict = {
    "style": "island",
    "seconds": True,
    "clock24": True,
    "opacity": 0.90,
    "visualizer": "hover",
    "order": DEFAULT_ORDER,
    "modules": {name: True for name in MODULES},
}

OPACITY_MIN = 0.40
OPACITY_MAX = 1.00

# Same sensor preferences as waybar/scripts/generate-hardware-local.py
HWMON_ROOT = Path("/sys/class/hwmon")
CPU_DRIVERS = ("k10temp", "zenpower", "coretemp", "cpu_thermal")
CPU_LABEL_PRIORITY = ("Tctl", "Package id 0", "Tdie", "CPU")
GPU_DRIVERS = ("amdgpu", "radeon", "nouveau", "i915", "xe")
GPU_LABEL_PRIORITY = ("edge", "junction", "mem")


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def fail(message: str) -> None:
    emit({"ok": False, "message": message})
    raise SystemExit(1)


def clamp(value: float) -> float:
    return max(OPACITY_MIN, min(OPACITY_MAX, value))


def on_off(raw: str) -> bool:
    if raw in ("on", "true", "1"):
        return True
    if raw in ("off", "false", "0"):
        return False
    fail("Expected on or off.")
    return False


# ---------------------------------------------------------------------------
# State file
# ---------------------------------------------------------------------------

def clean_order(items) -> list[str]:
    """Known ids once each, in the given order; missing ones appended."""
    order: list[str] = []
    for item in items:
        if item in MODULES and item not in order:
            order.append(item)
    for item in DEFAULT_ORDER:
        if item not in order:
            order.append(item)
    return order


def load() -> dict:
    state = json.loads(json.dumps(DEFAULTS))

    try:
        saved = json.loads(STATE.read_text())
    except (OSError, ValueError):
        return state

    if not isinstance(saved, dict):
        return state

    if saved.get("style") in ("island", "waybar"):
        state["style"] = saved["style"]

    for key in ("seconds", "clock24"):
        if isinstance(saved.get(key), bool):
            state[key] = saved[key]

    opacity = saved.get("opacity")
    if isinstance(opacity, (int, float)) and not isinstance(opacity, bool):
        state["opacity"] = clamp(float(opacity))

    if saved.get("visualizer") in VISUALIZER_MODES:
        state["visualizer"] = saved["visualizer"]

    if isinstance(saved.get("order"), list):
        state["order"] = clean_order(saved["order"])

    modules = saved.get("modules")
    if isinstance(modules, dict):
        for name in MODULES:
            if isinstance(modules.get(name), bool):
                state["modules"][name] = modules[name]

    return state


def save(state: dict) -> None:
    DIR.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(state, indent=2) + "\n"

    fd, tmp = tempfile.mkstemp(dir=str(DIR), prefix=".topbar-")
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

    ping_island()


def ping_island() -> None:
    """Tell a running island bar to re-read its settings (best effort)."""
    try:
        subprocess.Popen(
            ["qs", "-p", str(ISLAND_QML), "ipc", "call", "topbar", "reload"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Waybar sync (best effort: the island never depends on these)
# ---------------------------------------------------------------------------

def run_quiet(args: list[str]) -> dict | None:
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None

    try:
        return json.loads(proc.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return None


def waybar_opacity() -> float | None:
    if not WAYBAR_OPACITY_HELPER.exists():
        return None

    data = run_quiet(["python3", str(WAYBAR_OPACITY_HELPER), "get"])
    if data and data.get("ok") and isinstance(data.get("opacity"), (int, float)):
        return float(data["opacity"])

    return None


def sync_waybar_seconds(enabled: bool) -> None:
    if CLOCK_HELPER.exists():
        run_quiet(["python3", str(CLOCK_HELPER), "set", "on" if enabled else "off"])


def sync_waybar_opacity(value: float) -> None:
    if WAYBAR_OPACITY_HELPER.exists():
        run_quiet(["python3", str(WAYBAR_OPACITY_HELPER), "set", f"{value:.3f}"])


def restart_bar() -> None:
    """Start the selected bar (and stop the other) without waiting for it."""
    if not BAR_SCRIPT.exists():
        return

    subprocess.Popen(
        ["sh", str(BAR_SCRIPT), "start"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def get() -> None:
    state = load()
    result = {"ok": True, **state}

    # The slider shows what the visible bar actually uses.
    if state["style"] == "waybar":
        value = waybar_opacity()
        if value is not None:
            result["opacity"] = round(value, 3)

    emit(result)


def set_value(key: str, raw: str) -> None:
    state = load()
    message = ""

    if key == "style":
        if raw not in ("island", "waybar"):
            fail("Style must be island or waybar.")
        state["style"] = raw
        save(state)
        restart_bar()
        message = "Top bar: " + ("Island" if raw == "island" else "Waybar") + "."

    elif key == "seconds":
        state["seconds"] = on_off(raw)
        save(state)
        sync_waybar_seconds(state["seconds"])
        message = "Seconds " + ("on." if state["seconds"] else "off.")

    elif key == "clock24":
        state["clock24"] = on_off(raw)
        save(state)
        message = ("24-hour" if state["clock24"] else "12-hour") + " clock."

    elif key == "opacity":
        try:
            value = clamp(float(raw))
        except ValueError:
            fail("Invalid opacity.")
            return
        state["opacity"] = round(value, 3)
        save(state)
        sync_waybar_opacity(value)
        message = f"Top bar opacity {round(value * 100)}%."

    elif key == "visualizer":
        if raw not in VISUALIZER_MODES:
            fail("Visualizer must be hover, always or off.")
        state["visualizer"] = raw
        save(state)

    elif key == "order":
        if raw == "default":
            state["order"] = list(DEFAULT_ORDER)
        else:
            state["order"] = clean_order(raw.split(","))
        save(state)

    elif key.startswith("module.") and key[7:] in MODULES:
        state["modules"][key[7:]] = on_off(raw)
        save(state)

    else:
        fail(f"Unknown setting: {key}")

    emit({"ok": True, **state, "message": message})


def read_text(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def find_sensor(drivers, label_priority) -> str | None:
    fallback = None

    for hwmon in sorted(HWMON_ROOT.glob("hwmon*")):
        if read_text(hwmon / "name") not in drivers:
            continue

        inputs = sorted(hwmon.glob("temp*_input"))
        if not inputs:
            continue

        labels = {
            path: read_text(hwmon / (path.name.removesuffix("_input") + "_label"))
            for path in inputs
        }

        for wanted in label_priority:
            for path, label in labels.items():
                if label == wanted:
                    return str(path)

        if fallback is None:
            fallback = str(inputs[0])

    return fallback


def sensors() -> None:
    emit({
        "ok": True,
        "cpu": find_sensor(CPU_DRIVERS, CPU_LABEL_PRIORITY),
        "gpu": find_sensor(GPU_DRIVERS, GPU_LABEL_PRIORITY),
    })


def main() -> None:
    args = sys.argv[1:]

    if args == ["get"]:
        get()
    elif len(args) == 3 and args[0] == "set":
        set_value(args[1], args[2])
    elif args == ["sensors"]:
        sensors()
    elif args == ["init"]:
        if not STATE.exists():
            save(load())
        emit({"ok": True})
    else:
        fail("Usage: get | set <key> <value> | sensors | init")


if __name__ == "__main__":
    main()
