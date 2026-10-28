#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

MIN_TEMP = 2500
MAX_TEMP = 6500
DEFAULT_TEMP = 4500

STATE_HOME = Path(
    os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))
)
STATE_FILE = STATE_HOME / "yakushi" / "nightlight.json"


def clamp_temperature(value: int) -> int:
    return max(MIN_TEMP, min(MAX_TEMP, value))


def default_state() -> dict:
    return {"enabled": False, "temperature": DEFAULT_TEMP}


def load_state() -> dict:
    try:
        data = json.loads(STATE_FILE.read_text())
        return {
            "enabled": bool(data.get("enabled", False)),
            "temperature": clamp_temperature(
                int(data.get("temperature", DEFAULT_TEMP))
            ),
        }
    except (FileNotFoundError, ValueError, TypeError, json.JSONDecodeError):
        return default_state()


def save_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state, indent=2) + "\n")
    tmp.replace(STATE_FILE)


def emit(ok: bool, state: dict, message: str = "") -> int:
    print(
        json.dumps(
            {
                "ok": ok,
                "enabled": bool(state["enabled"]),
                "temperature": int(state["temperature"]),
                "message": message,
            }
        ),
        flush=True,
    )
    return 0 if ok else 1


def run_hyprsunset(*args: str) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            ["hyprctl", "hyprsunset", *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=2,
            check=False,
        )
    except FileNotFoundError:
        return False, "hyprctl is not installed."
    except subprocess.TimeoutExpired:
        return False, "hyprsunset IPC timed out."

    if result.returncode == 0:
        return True, ""

    detail = (result.stderr or result.stdout).strip()
    if detail:
        detail = detail.splitlines()[-1]
    return False, detail or f"hyprctl exited with code {result.returncode}."


def parse_temperature(raw: str) -> int:
    try:
        temperature = int(raw)
    except ValueError:
        raise SystemExit("Temperature must be an integer.")

    if not MIN_TEMP <= temperature <= MAX_TEMP:
        raise SystemExit(
            f"Temperature must be between {MIN_TEMP} and {MAX_TEMP} K."
        )

    return temperature


def main() -> int:
    state = load_state()
    command = sys.argv[1] if len(sys.argv) > 1 else "status"

    if command == "status":
        return emit(True, state)

    if command == "restore":
        if state["enabled"]:
            ok, message = run_hyprsunset(
                "temperature", str(state["temperature"])
            )
            return emit(ok, state, message or "Night Light restored.")

        ok, message = run_hyprsunset("identity")
        return emit(ok, state, message or "Night Light is disabled.")

    if command == "set":
        if len(sys.argv) != 3:
            raise SystemExit("Usage: yakushi-nightlightctl.py set TEMPERATURE")

        temperature = parse_temperature(sys.argv[2])
        candidate = dict(state)
        candidate["enabled"] = True
        candidate["temperature"] = temperature

        ok, message = run_hyprsunset("temperature", str(temperature))
        if not ok:
            return emit(False, state, message)

        save_state(candidate)
        return emit(True, candidate, "Night Light enabled.")

    if command == "temperature":
        if len(sys.argv) != 3:
            raise SystemExit(
                "Usage: yakushi-nightlightctl.py temperature TEMPERATURE"
            )

        temperature = parse_temperature(sys.argv[2])
        candidate = dict(state)
        candidate["temperature"] = temperature

        if state["enabled"]:
            ok, message = run_hyprsunset("temperature", str(temperature))
            if not ok:
                return emit(False, state, message)

        save_state(candidate)
        return emit(True, candidate, "Night Light temperature saved.")

    if command == "off":
        ok, message = run_hyprsunset("identity")
        if not ok:
            return emit(False, state, message)

        state["enabled"] = False
        save_state(state)
        return emit(True, state, "Night Light disabled.")

    raise SystemExit(
        "Usage: yakushi-nightlightctl.py "
        "status|restore|set TEMPERATURE|temperature TEMPERATURE|off"
    )


if __name__ == "__main__":
    raise SystemExit(main())
