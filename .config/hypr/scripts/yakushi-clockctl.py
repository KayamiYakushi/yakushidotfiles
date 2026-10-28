#!/usr/bin/env python3
"""Toggle seconds in the Waybar clock.

Commands:
    get            Print the current state as JSON.
    set on|off     Enable or disable seconds.

Why the calendar tooltip moves while seconds are on
---------------------------------------------------
With interval 1, Waybar's clock module rebuilds its calendar tooltip and
re-resolves CSS classes on the label EVERY second. That is wasted CPU, and it
keeps invalidating the label's style, which breaks the hover font-size
transition. So while seconds are on:

  * "clock"       -> interval 1, tooltip off (only the text is refreshed)
  * "clock#date"  -> carries the calendar tooltip (refreshed once a minute)

Turning seconds off restores the original layout exactly.

Nothing runs in the background; this script edits the config, asks Waybar
to reload, and exits. The 12h/24h layout is preserved: only ':%S' is
added or removed.
"""
from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

CONFIG = Path.home() / ".config/waybar/config.jsonc"

TIME_BLOCK = "clock"
DATE_BLOCK = "clock#date"

CALENDAR_TOOLTIP = '"<tt><small>{calendar}</small></tt>"'
CALENDAR_OBJECT = '{ "mode": "month", "format": { "today": "<b><u>{}</u></b>" } }'


def emit(obj: dict) -> None:
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def fail(message: str, code: int = 1) -> None:
    emit({"ok": False, "message": message})
    raise SystemExit(code)


# ---------------------------------------------------------------------------
# Minimal, string-aware JSONC helpers (no dependencies)
# ---------------------------------------------------------------------------

def skip_trivia(text: str, i: int) -> int:
    """Skip whitespace, // comments and /* */ comments."""
    n = len(text)
    while i < n:
        if text[i].isspace():
            i += 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j == -1 else j + 1
        elif text.startswith("/*", i):
            j = text.find("*/", i)
            i = n if j == -1 else j + 2
        else:
            break
    return i


def read_string(text: str, i: int) -> int:
    """`i` points at an opening quote; return the index after the closing one."""
    i += 1
    while i < len(text):
        if text[i] == "\\":
            i += 2
        elif text[i] == '"':
            return i + 1
        else:
            i += 1
    fail("Malformed Waybar config (unterminated string).")
    raise SystemExit(1)


def read_value_end(text: str, i: int) -> int:
    """`i` points at the first char of a value; return the index after it."""
    if text[i] == '"':
        return read_string(text, i)

    if text[i] in "{[":
        depth = 0
        while i < len(text):
            ch = text[i]
            if ch == '"':
                i = read_string(text, i)
                continue
            if ch in "{[":
                depth += 1
            elif ch in "}]":
                depth -= 1
                if depth == 0:
                    return i + 1
            i += 1
        fail("Malformed Waybar config (unbalanced brackets).")

    j = i
    while j < len(text) and text[j] not in ",}\n\r":
        j += 1
    while j > i and text[j - 1].isspace():
        j -= 1
    return j


def find_block(text: str, name: str) -> tuple[int, int] | None:
    """Return (start, end) of the body of the top-level object `name`."""
    match = re.search(r'"' + re.escape(name) + r'"\s*:\s*\{', text)
    if not match:
        return None

    start = match.end()
    i = start
    while i < len(text):
        i = skip_trivia(text, i)
        if i >= len(text):
            break
        if text[i] == "}":
            return start, i
        if text[i] == ",":
            i += 1
            continue
        if text[i] != '"':
            fail("Malformed Waybar config (unexpected token).")
        key_end = read_string(text, i)
        i = skip_trivia(text, key_end)
        if i >= len(text) or text[i] != ":":
            fail("Malformed Waybar config (expected ':').")
        i = skip_trivia(text, i + 1)
        i = read_value_end(text, i)

    fail(f'Malformed Waybar config (unterminated "{name}" block).')
    raise SystemExit(1)


def scan_keys(body: str) -> dict[str, tuple[int, int, int]]:
    """Depth-0 keys of an object body -> (key_start, value_start, value_end)."""
    keys: dict[str, tuple[int, int, int]] = {}
    i = 0
    while i < len(body):
        i = skip_trivia(body, i)
        if i >= len(body):
            break
        if body[i] == ",":
            i += 1
            continue
        if body[i] != '"':
            fail("Malformed Waybar config (unexpected token).")
        key_start = i
        key_end = read_string(body, i)
        key = body[key_start + 1:key_end - 1]
        i = skip_trivia(body, key_end)
        i = skip_trivia(body, i + 1)  # past ':'
        value_start = i
        i = read_value_end(body, i)
        keys[key] = (key_start, value_start, i)
    return keys


def get_value(body: str, key: str) -> str | None:
    found = scan_keys(body).get(key)
    return None if found is None else body[found[1]:found[2]]


def set_key(body: str, key: str, literal: str) -> str:
    found = scan_keys(body).get(key)
    if found:
        return body[:found[1]] + literal + body[found[2]:]
    # Insert as the first key so no trailing-comma handling is ever needed.
    indent = re.match(r"\s*", body).group(0) or "\n        "
    if "\n" not in indent:
        indent = "\n        "
    return f'{indent}"{key}": {literal},' + body


def remove_key(body: str, key: str) -> str:
    found = scan_keys(body).get(key)
    if not found:
        return body

    key_start, _, value_end = found
    after = value_end
    j = skip_trivia(body, after)

    if j < len(body) and body[j] == ",":
        # Drop the key, its comma and the whitespace up to the next token.
        line_start = body.rfind("\n", 0, key_start)
        cut_from = line_start if line_start != -1 and body[line_start + 1:key_start].strip() == "" else key_start
        k = j + 1
        return body[:cut_from] + body[k:]

    # Last key: drop it together with the comma that precedes it.
    p = key_start
    while p > 0 and body[p - 1].isspace():
        p -= 1
    if p > 0 and body[p - 1] == ",":
        p -= 1
    return body[:p] + body[value_end:]


def replace_body(text: str, span: tuple[int, int], body: str) -> str:
    return text[:span[0]] + body + text[span[1]:]


# ---------------------------------------------------------------------------
# Format helpers
# ---------------------------------------------------------------------------

def seconds_enabled(fmt: str) -> bool:
    return "%S" in fmt or "%T" in fmt


def with_seconds(fmt: str) -> str:
    if seconds_enabled(fmt) or "%M" not in fmt:
        return fmt
    return fmt.replace("%M", "%M:%S", 1)


def without_seconds(fmt: str) -> str:
    return fmt.replace(":%S", "").replace("%S", "")


def read_format(text: str) -> str:
    span = find_block(text, TIME_BLOCK)
    if not span:
        fail('Could not find the "clock" module in the Waybar config.')

    raw = get_value(text[span[0]:span[1]], "format")
    if raw is None or not raw.startswith('"'):
        fail('The clock module has no "format" entry.')

    return json.loads(raw)


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

def write_atomic(path: Path, content: str) -> None:
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    target = path.resolve()
    fd, tmp_name = tempfile.mkstemp(dir=str(target.parent), prefix=".clockctl-")
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(content)
        os.chmod(tmp_name, mode)
        os.replace(tmp_name, target)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def reload_waybar() -> None:
    proc = subprocess.run(["pgrep", "-x", "waybar"], text=True, capture_output=True)

    for line in proc.stdout.splitlines():
        if line.strip().isdigit():
            try:
                os.kill(int(line.strip()), signal.SIGUSR2)
            except ProcessLookupError:
                pass


def set_state(enable: bool) -> None:
    if not CONFIG.exists():
        fail(f"Missing {CONFIG}")

    text = CONFIG.read_text()

    # --- time clock -------------------------------------------------------
    span = find_block(text, TIME_BLOCK)
    if not span:
        fail('Could not find the "clock" module in the Waybar config.')

    body = text[span[0]:span[1]]
    raw_fmt = get_value(body, "format")
    if raw_fmt is None or not raw_fmt.startswith('"'):
        fail('The clock module has no "format" entry.')

    current = json.loads(raw_fmt)
    new_fmt = with_seconds(current) if enable else without_seconds(current)

    body = set_key(body, "format", json.dumps(new_fmt, ensure_ascii=False))
    body = set_key(body, "interval", "1" if enable else "60")

    if enable:
        body = set_key(body, "tooltip", "false")
    else:
        body = remove_key(body, "tooltip")

    text = replace_body(text, span, body)

    # --- date clock (carries the calendar while seconds are on) ------------
    span = find_block(text, DATE_BLOCK)
    if span:
        body = text[span[0]:span[1]]

        if enable:
            body = set_key(body, "tooltip", "true")
            body = set_key(body, "tooltip-format", CALENDAR_TOOLTIP)
            body = set_key(body, "calendar", CALENDAR_OBJECT)
        else:
            body = set_key(body, "tooltip", "false")
            body = remove_key(body, "tooltip-format")
            body = remove_key(body, "calendar")

        text = replace_body(text, span, body)

    if text != CONFIG.read_text():
        write_atomic(CONFIG, text)
        reload_waybar()

    emit(
        {
            "ok": True,
            "seconds": enable,
            "message": "Seconds enabled." if enable else "Seconds disabled.",
        }
    )


def main() -> None:
    if len(sys.argv) < 2:
        fail("Usage: get | set on|off")

    cmd = sys.argv[1]

    if cmd == "get":
        if not CONFIG.exists():
            fail(f"Missing {CONFIG}")
        emit({"ok": True, "seconds": seconds_enabled(read_format(CONFIG.read_text()))})
    elif cmd == "set" and len(sys.argv) >= 3 and sys.argv[2] in ("on", "off"):
        set_state(sys.argv[2] == "on")
    else:
        fail("Usage: get | set on|off")


if __name__ == "__main__":
    main()
