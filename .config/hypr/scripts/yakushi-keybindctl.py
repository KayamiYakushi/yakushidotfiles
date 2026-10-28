#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
KEYBINDS = HOME / ".config/hypr/keybinds.lua"
DISABLED = HOME / ".config/hypr/yakushi-disabled-binds.txt"
LAST_GOOD = HOME / ".config/hypr/keybinds.lua.yakushi-last-good"
LAST_DISABLED = HOME / ".config/hypr/yakushi-disabled-binds.txt.yakushi-last-good"

MARKER_RE = re.compile(
    r"^\s*--\s*YAKUSHI_BIND\s+([^|]+)\|([^|]+)\|([^|]+?)(?:\|(danger))?\s*$"
)
YBIND_RE = re.compile(
    r'^(\s*yakushi_bind\("([^"]+)",\s*)("([^"]+)")(\s*,.*)$'
)

def emit(obj):
    print(json.dumps(obj, ensure_ascii=False))

def fail(message, code=1):
    emit({"ok": False, "message": message})
    raise SystemExit(code)

def disabled_ids():
    if not DISABLED.exists():
        return set()

    return {
        line.strip()
        for line in DISABLED.read_text().splitlines()
        if line.strip()
    }

def write_disabled(values):
    values = sorted(set(values))
    DISABLED.parent.mkdir(parents=True, exist_ok=True)
    DISABLED.write_text(
        ("\n".join(values) + "\n") if values else ""
    )

def snapshot():
    shutil.copy2(KEYBINDS, LAST_GOOD)

    if DISABLED.exists():
        shutil.copy2(DISABLED, LAST_DISABLED)
    elif LAST_DISABLED.exists():
        LAST_DISABLED.unlink()

def rollback():
    if LAST_GOOD.exists():
        shutil.copy2(LAST_GOOD, KEYBINDS)

    if LAST_DISABLED.exists():
        shutil.copy2(LAST_DISABLED, DISABLED)
    elif DISABLED.exists():
        DISABLED.unlink()

def reload_hyprland():
    proc = subprocess.run(
        ["hyprctl", "reload"],
        text=True,
        capture_output=True,
    )

    output = (proc.stdout + proc.stderr).strip()
    ok = proc.returncode == 0 and "ok" in output.lower()
    return ok, output

def normalize(combo):
    combo = combo.strip()

    if not combo:
        return ""

    direct = {
        "XF86AUDIORAISEVOLUME": "XF86AudioRaiseVolume",
        "XF86AUDIOLOWERVOLUME": "XF86AudioLowerVolume",
        "XF86AUDIOMUTE": "XF86AudioMute",
        "XF86AUDIOPLAY": "XF86AudioPlay",
        "XF86AUDIONEXT": "XF86AudioNext",
        "XF86AUDIOPREV": "XF86AudioPrev",
    }

    upper = combo.upper()

    if upper in direct:
        return direct[upper]

    aliases = {
        "META": "SUPER",
        "WIN": "SUPER",
        "WINDOWS": "SUPER",
        "CONTROL": "CTRL",
    }

    parts = [p.strip() for p in combo.split("+") if p.strip()]
    mods = []
    key = ""

    for part in parts:
        normalized = aliases.get(part.upper(), part.upper())

        if normalized in {"SUPER", "CTRL", "ALT", "SHIFT"}:
            if normalized not in mods:
                mods.append(normalized)
        else:
            key = part

    order = ["SUPER", "CTRL", "ALT", "SHIFT"]
    mods = [m for m in order if m in mods]

    if not key:
        return " + ".join(mods)

    key_aliases = {
        "`": "GRAVE",
        "RETURN": "Enter",
        "ENTER": "Enter",
        "ESC": "Escape",
        "DEL": "Delete",
        "SPACEBAR": "Space",
    }

    key = key_aliases.get(key.upper(), key)

    if len(key) == 1:
        key = key.upper()
    elif key.upper() == "GRAVE":
        key = "GRAVE"
    elif key.lower().startswith("mouse:"):
        key = key.lower()
    elif key.lower() in {"mouse_up", "mouse_down"}:
        key = key.lower()
    elif key.lower().startswith("code:"):
        key = key.lower()
    elif not key.startswith("XF86"):
        key = key[0].upper() + key[1:]

    return " + ".join(mods + [key]) if mods else key

def parse():
    if not KEYBINDS.exists():
        fail(f"Missing {KEYBINDS}")

    lines = KEYBINDS.read_text().splitlines()
    disabled = disabled_ids()
    entries = []

    for i, line in enumerate(lines):
        marker = MARKER_RE.match(line)

        if not marker:
            continue

        bind_id, category, label, danger = marker.groups()
        bind_id = bind_id.strip()

        for j in range(i + 1, min(i + 10, len(lines))):
            if lines[j].strip().startswith("-- YAKUSHI_BIND"):
                break

            match = YBIND_RE.match(lines[j])

            if match and match.group(2) == bind_id:
                entries.append({
                    "id": bind_id,
                    "category": category.strip(),
                    "label": label.strip(),
                    "combo": match.group(4),
                    "danger": bool(danger),
                    "bindEnabled": bind_id not in disabled,
                    "line": j + 1,
                })
                break

    return entries

def find_active_conflict(entries, bind_id, combo):
    normalized = normalize(combo).casefold()

    for entry in entries:
        if entry["id"] == bind_id:
            continue

        # Disabled bindings do NOT reserve their shortcut.
        if not entry["bindEnabled"]:
            continue

        if normalize(entry["combo"]).casefold() == normalized:
            return entry

    return None

def mutate_then_reload(mutator):
    snapshot()
    mutator()

    ok, output = reload_hyprland()

    if not ok:
        rollback()
        reload_hyprland()
        fail(
            "Hyprland rejected the change; previous state was restored. "
            + output
        )

def set_combo(bind_id, combo):
    combo = normalize(combo)

    if not combo:
        fail("A shortcut cannot be empty. Use OFF to disable it.")

    entries = parse()
    target = next((e for e in entries if e["id"] == bind_id), None)

    if target is None:
        fail(f"Unknown binding: {bind_id}")

    # Only ACTIVE bindings participate in conflict detection.
    # A disabled binding keeps its remembered shortcut without reserving it.
    if target["bindEnabled"]:
        conflict = find_active_conflict(entries, bind_id, combo)

        if conflict:
            fail(
                f"{combo} is already assigned to active binding "
                f"{conflict['label']}. Disable that binding first."
            )

    if target["danger"]:
        parts = combo.split(" + ")

        if not any(x in parts for x in ("SUPER", "CTRL", "ALT", "SHIFT")):
            fail("Dangerous actions must keep at least one modifier.")

    def do_change():
        lines = KEYBINDS.read_text().splitlines()
        idx = target["line"] - 1
        match = YBIND_RE.match(lines[idx])

        if not match:
            fail("Binding source changed unexpectedly. No changes made.")

        escaped = combo.replace("\\", "\\\\").replace('"', '\\"')
        lines[idx] = f'{match.group(1)}"{escaped}"{match.group(5)}'
        KEYBINDS.write_text("\n".join(lines) + "\n")

    mutate_then_reload(do_change)

    emit({
        "ok": True,
        "message": f"{target['label']} → {combo}",
        "combo": combo,
    })

def set_enabled(bind_id, enabled):
    entries = parse()
    target = next((e for e in entries if e["id"] == bind_id), None)

    if target is None:
        fail(f"Unknown binding: {bind_id}")

    disabled = disabled_ids()

    # Re-enabling must not create two active bindings on the same combo.
    if enabled:
        conflict = find_active_conflict(
            entries,
            bind_id,
            target["combo"],
        )

        if conflict:
            fail(
                f"Cannot enable {target['label']}: "
                f"{target['combo']} is currently used by "
                f"{conflict['label']}. Change one shortcut first."
            )

    def do_change():
        if enabled:
            disabled.discard(bind_id)
        else:
            disabled.add(bind_id)

        write_disabled(disabled)

    mutate_then_reload(do_change)

    emit({
        "ok": True,
        "message": (
            f"{target['label']} enabled."
            if enabled
            else f"{target['label']} disabled. Shortcut preserved and released."
        ),
        "bindEnabled": enabled,
    })

def restore():
    if not LAST_GOOD.exists():
        fail("No previous Yakushi keybind state is available.")

    current = KEYBINDS.with_suffix(".lua.yakushi-before-restore")
    current_disabled = DISABLED.with_suffix(
        ".txt.yakushi-before-restore"
    )

    shutil.copy2(KEYBINDS, current)

    if DISABLED.exists():
        shutil.copy2(DISABLED, current_disabled)

    rollback()
    ok, output = reload_hyprland()

    if not ok:
        shutil.copy2(current, KEYBINDS)

        if current_disabled.exists():
            shutil.copy2(current_disabled, DISABLED)

        reload_hyprland()
        fail(
            "Restore failed; current state was kept. "
            + output
        )

    emit({
        "ok": True,
        "message": "Restored previous keybind state."
    })

def main():
    if len(sys.argv) < 2:
        fail(
            "Usage: list | set <id> <combo> | "
            "enable <id> | disable <id> | restore"
        )

    cmd = sys.argv[1]

    if cmd == "list":
        emit(parse())
    elif cmd == "set" and len(sys.argv) >= 4:
        set_combo(sys.argv[2], sys.argv[3])
    elif cmd == "enable" and len(sys.argv) >= 3:
        set_enabled(sys.argv[2], True)
    elif cmd == "disable" and len(sys.argv) >= 3:
        set_enabled(sys.argv[2], False)
    elif cmd == "restore":
        restore()
    else:
        fail("Invalid command.")

if __name__ == "__main__":
    main()
