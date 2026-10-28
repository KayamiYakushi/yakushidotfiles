#!/usr/bin/env python3
"""Wi-Fi for Settings -> Network (through NetworkManager's nmcli).

Commands (each prints one JSON object with the current state):
    state                 radio on/off + the networks NetworkManager knows now
    scan                  ask for a fresh scan first, then `state`
    radio on|off          switch Wi-Fi
    join <ssid> [pass]    connect (password only for secured networks)
    leave <ssid>          disconnect

A network seen through several access points is listed once, with the
strongest signal; the connected one comes first. Runs only when called.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time


def nmcli(*args: str, timeout: int = 30) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(["nmcli", *args], capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return subprocess.CompletedProcess(args, 127, "", "nmcli is not installed")
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, "", "nmcli timed out")


def split_terse(line: str, fields: int) -> list[str]:
    """nmcli -t separates with ':' and writes a ':' inside a value as '\\:'."""
    out, cur, i = [], [], 0
    while i < len(line):
        c = line[i]
        if c == "\\" and i + 1 < len(line):
            cur.append(line[i + 1])
            i += 2
            continue
        if c == ":" and len(out) < fields - 1:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return out


def radio_on() -> bool:
    return nmcli("radio", "wifi").stdout.strip() == "enabled"


def networks() -> list[dict]:
    res = nmcli("-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no")
    best: dict[str, dict] = {}
    for line in res.stdout.splitlines():
        parts = split_terse(line.strip(), 4)
        if len(parts) != 4 or not parts[1]:
            continue
        in_use, ssid, signal, security = parts
        net = {
            "ssid": ssid,
            "signal": int(signal) if signal.isdigit() else 0,
            "secured": security not in ("", "--"),
            "connected": in_use.strip() == "*",
        }
        old = best.get(ssid)
        if old is None:
            best[ssid] = net
        else:
            old["connected"] = old["connected"] or net["connected"]
            old["signal"] = max(old["signal"], net["signal"])
            old["secured"] = old["secured"] or net["secured"]
    return sorted(best.values(), key=lambda n: (not n["connected"], -n["signal"], n["ssid"].lower()))


def state(**extra) -> None:
    on = radio_on()
    print(json.dumps({"ok": True, "radio": on, "networks": networks() if on else [], **extra}))


def main() -> None:
    args = sys.argv[1:]
    if args == ["state"]:
        state()
    elif args == ["scan"]:
        nmcli("device", "wifi", "rescan")
        time.sleep(1.2)            # give the driver a moment to report
        state()
    elif len(args) == 2 and args[0] == "radio" and args[1] in ("on", "off"):
        nmcli("radio", "wifi", args[1])
        time.sleep(0.5 if args[1] == "off" else 2.0)
        state()
    elif len(args) in (2, 3) and args[0] == "join":
        cmd = ["device", "wifi", "connect", args[1]]
        if len(args) == 3:
            cmd += ["password", args[2]]
        res = nmcli(*cmd, timeout=60)
        message = f"Connected to {args[1]}." if res.returncode == 0 else \
            (res.stderr.strip().splitlines() or ["Could not connect."])[-1].removeprefix("Error: ")
        state(joined=res.returncode == 0, message=message)
    elif len(args) == 2 and args[0] == "leave":
        res = nmcli("connection", "down", "id", args[1])
        state(message=f"Disconnected from {args[1]}." if res.returncode == 0 else "Could not disconnect.")
    else:
        print(json.dumps({"ok": False, "message": "Usage: state | scan | radio on|off | join <ssid> [password] | leave <ssid>"}))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
