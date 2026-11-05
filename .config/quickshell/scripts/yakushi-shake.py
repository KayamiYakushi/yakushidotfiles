#!/usr/bin/env python3
"""Shake to find: the cursor grows while you shake the mouse.

    yakushi-shake.py           run (Settings -> Input -> Cursor starts it)
    yakushi-shake.py --login   run only if shake to find is switched on

Reads the cursor position from Hyprland's own socket (no hyprctl processes,
no plugins). On a shake it grows the REAL cursor - clicks keep working, it
never disappears - through Yakushi-Shake, a tiny theme with your arrow, hand
and text cursor pre-scaled to a few sizes (made by yakushi-cursorctl.py).
Hyprland loads that in a blink, so growing and shrinking are smooth. Your
full theme comes back once the mouse has been still for a moment, when a
reload cannot be noticed.

Nearly idle when the mouse is still: 5 checks a second then, 40 while it
moves. A shake = the path the pointer travelled in the last 0.5 s is much
longer than the box it stayed in (back and forth, like KDE does it).
"""
from __future__ import annotations

import math
import os
import re
import signal
import socket
import sys
import time
from collections import deque
from pathlib import Path

HOME = Path.home()
HERE = Path(__file__).resolve().parent
LOCAL = HOME / ".config/hypr/cursor.local.lua"
INFO = HOME / ".cache/yakushi/cursors/shake.json"
PIDFILE = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "yakushi" / "shake.pid"
HELPER = "Yakushi-Shake"

WINDOW = 0.5          # seconds of history looked at
MIN_PATH = 700        # px the pointer must travel in that time
RATIO = 3.2           # path length / box diagonal that counts as a shake
HOLD = 0.35           # stay big this long after the shaking stops (Settings: -- shake-hold:)
STEP_UP = 0.018       # seconds between sizes while growing
STEP_DOWN = 0.028     # ... while shrinking
STILL = 0.8           # mouse still this long -> back to the full theme
FAST, SLOW = 1 / 40, 1 / 5


def hypr_socket() -> str | None:
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    run = os.environ.get("XDG_RUNTIME_DIR")
    if not sig or not run:
        return None
    path = Path(run) / "hypr" / sig / ".socket.sock"
    return str(path) if path.exists() else None


def ask(sock_path: str, request: str) -> str:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(0.5)
        s.connect(sock_path)
        s.sendall(request.encode())
        chunks = []
        while True:
            part = s.recv(4096)
            if not part:
                break
            chunks.append(part)
    return b"".join(chunks).decode(errors="ignore")


def hold_time(text: str) -> float:
    m = re.search(r"^-- shake-hold: ([\d.]+)$", text, re.M)
    try:
        return min(3.0, max(0.1, float(m.group(1)))) if m else HOLD
    except ValueError:
        return HOLD


def settings() -> tuple[str, int, bool]:
    """theme, size and whether shake to find is on (cursor.local.lua)"""
    try:
        text = LOCAL.read_text()
    except OSError:
        text = ""
    theme = re.search(r'"XCURSOR_THEME",\s*"([^"]*)"', text)
    size = re.search(r'"XCURSOR_SIZE",\s*"(\d+)"', text)
    return (
        theme.group(1) if theme else os.environ.get("XCURSOR_THEME", "Adwaita"),
        int(size.group(1)) if size else int(os.environ.get("XCURSOR_SIZE", "24") or 24),
        re.search(r"^-- shake: on$", text, re.M) is not None,
    )


def helper_sizes(theme: str, base: int) -> list[int]:
    """sizes of the helper theme, rebuilt when the theme or size changed"""
    import json                                  # only needed here: keeps the
    import importlib.util                        # resident process small
    try:
        info = json.loads(INFO.read_text())
        if info.get("theme") == theme and info.get("base") == base and \
                (HOME / ".local/share/icons" / HELPER / "cursors/default").exists():
            return info["sizes"]
    except (OSError, ValueError):
        pass
    try:
        spec = importlib.util.spec_from_file_location("cursorctl", HERE / "yakushi-cursorctl.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.write_shake_theme()["sizes"]
    except Exception as e:                       # never fatal: then no growing
        print(f"yakushi-shake: helper theme failed ({e})", file=sys.stderr)
        return []


def is_shake(trail: deque) -> bool:
    if len(trail) < 6:
        return False
    pts = list(trail)
    xs = [p[1] for p in pts]
    ys = [p[2] for p in pts]
    path = sum(math.hypot(b[1] - a[1], b[2] - a[2]) for a, b in zip(pts, pts[1:]))
    diag = math.hypot(max(xs) - min(xs), max(ys) - min(ys))
    return path >= MIN_PATH and path >= RATIO * max(diag, 1.0)


def main() -> None:
    theme, base, on = settings()
    if "--login" in sys.argv and not on:
        return
    sock = hypr_socket()
    if sock is None:
        print("yakushi-shake: not inside Hyprland", file=sys.stderr)
        return

    PIDFILE.parent.mkdir(parents=True, exist_ok=True)
    try:                                   # one copy only (and really a copy of us:
        old = int(PIDFILE.read_text())     # a pid number gets reused by other programs)
        if old != os.getpid() and b"yakushi-shake.py" in Path(f"/proc/{old}/cmdline").read_bytes():
            return
    except (OSError, ValueError):
        pass
    PIDFILE.write_text(str(os.getpid()))
    sizes = helper_sizes(theme, base)

    # "full": your theme is loaded | "big": helper theme, grown |
    # "helper": helper theme at normal size, waiting to swap back
    st = {"mode": "full"}

    def setcursor(name: str, px: int) -> None:
        try:
            ask(sock, f"setcursor {name} {px}")
        except OSError:
            pass

    def restore() -> None:
        t, b, _ = settings()               # whatever Settings has now
        setcursor(t, b)
        st["mode"] = "full"

    def leave(*_):
        if st["mode"] != "full":
            restore()
        try:
            if PIDFILE.read_text().strip() == str(os.getpid()):
                PIDFILE.unlink()
        except OSError:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, leave)
    signal.signal(signal.SIGINT, leave)

    trail: deque = deque()
    last = None
    last_move = last_shake = 0.0
    delay = SLOW
    while True:
        time.sleep(delay)
        try:
            x, y = (float(v) for v in ask(sock, "cursorpos").split(","))
        except (OSError, ValueError):
            if hypr_socket() is None:      # Hyprland is gone
                leave()
            continue
        now = time.monotonic()
        moved = last is None or (x, y) != last
        last = (x, y)
        if moved:
            last_move = now
        delay = FAST if moved else SLOW

        trail.append((now, x, y))
        while trail and now - trail[0][0] > WINDOW:
            trail.popleft()
        shaking = is_shake(trail)

        if shaking:
            last_shake = now
            if st["mode"] != "big":
                try:                               # how long to stay big, from Settings
                    st["hold"] = hold_time(LOCAL.read_text())
                except OSError:
                    st["hold"] = HOLD
                t, b, _ = settings()               # picked up from Settings
                if (t, b) != (theme, base):
                    theme, base = t, b
                    sizes = helper_sizes(theme, base)
                for px in sizes[1:]:
                    setcursor(HELPER, px)
                    time.sleep(STEP_UP)
                if sizes:
                    st["mode"] = "big"
        elif st["mode"] == "big" and now - last_shake > st.get("hold", HOLD):
            for px in reversed(sizes[:-1]):
                setcursor(HELPER, px)
                time.sleep(STEP_DOWN)
            st["mode"] = "helper"
        elif st["mode"] == "helper" and now - last_move > STILL:
            restore()


if __name__ == "__main__":
    main()
