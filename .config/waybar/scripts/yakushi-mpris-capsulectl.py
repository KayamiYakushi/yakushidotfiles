#!/usr/bin/env python3
from pathlib import Path
import os
import signal
import subprocess
import sys

HOME = Path.home()
STATE = HOME / ".config/waybar/mpris-state.css"

def reload_waybar():
    p = subprocess.run(["pgrep", "-x", "waybar"], text=True, capture_output=True)
    if p.returncode != 0:
        return
    for line in p.stdout.splitlines():
        if line.strip().isdigit():
            try:
                os.kill(int(line.strip()), signal.SIGUSR2)
            except ProcessLookupError:
                pass

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in {"show", "hide"}:
        raise SystemExit("Usage: yakushi-mpris-capsulectl.py show|hide")

    wanted = (
        "/* visible: use base .modules-center style */\n"
        if sys.argv[1] == "show"
        else ".modules-center {\n    background-color: transparent;\n}\n"
    )

    current = STATE.read_text() if STATE.exists() else ""
    if current == wanted:
        return

    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".css.tmp")
    tmp.write_text(wanted)
    tmp.replace(STATE)
    reload_waybar()

if __name__ == "__main__":
    main()
