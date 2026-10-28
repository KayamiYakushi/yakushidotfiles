#!/usr/bin/env python3
"""Facts for Settings -> System, as one JSON object.

    yakushi-sysinfo.py          host, OS, kernel, user, CPU model, disk use
    yakushi-sysinfo.py disk     disk use only (refreshed once a minute)

Live numbers (CPU / GPU load, memory, uptime) are read by the page itself
from /proc and sysfs; the GPU model comes from yakushi-gpuinfo.py.
"""
import json
import os
import platform
import pwd
import shutil
import socket
import sys
from pathlib import Path


def read(path: str) -> str:
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ""


def os_name() -> str:
    for line in read("/etc/os-release").splitlines():
        if line.startswith("PRETTY_NAME="):
            return line.split("=", 1)[1].strip().strip('"')
    return platform.system()


def cpu_model() -> str:
    for line in read("/proc/cpuinfo").splitlines():
        if line.lower().startswith(("model name", "hardware")):
            return line.split(":", 1)[1].strip()
    return platform.processor() or "Unknown CPU"


def gib(n: float) -> str:
    """df -h style: 212G, 931G, 1.8T"""
    for unit, size in (("T", 1 << 40), ("G", 1 << 30), ("M", 1 << 20)):
        if n >= size:
            v = n / size
            return (f"{v:.1f}" if v < 10 else f"{v:.0f}") + unit
    return f"{n:.0f}B"


def disk() -> dict:
    u = shutil.disk_usage("/")
    # like df: what is used out of what this user can use
    frac = u.used / (u.used + u.free) if u.used + u.free else 0
    return {
        "storage": f"{gib(u.used)} / {gib(u.total)} ({round(frac * 100)}%)",
        "storageFraction": round(frac, 4),
    }


def everything() -> dict:
    try:
        user = pwd.getpwuid(os.getuid()).pw_name
    except KeyError:
        user = os.environ.get("USER", "")
    return {
        "host": read("/etc/hostname") or socket.gethostname(),
        "os": os_name(),
        "kernel": platform.release(),
        "user": user,
        "cpu": cpu_model(),
        **disk(),
    }


if __name__ == "__main__":
    print(json.dumps(disk() if sys.argv[1:] == ["disk"] else everything()))
