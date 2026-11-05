#!/usr/bin/env python3
"""What runs on this computer, and why. Used by Settings -> Tasks.

    yakushi-taskctl.py stream      one JSON line every 1.5 s: CPU, memory and
                                   every process, with a flag on the ones in
                                   trouble (runs only while the Tasks page is
                                   open, and stops with it)
    yakushi-taskctl.py why <pid>   where a process comes from, in plain words:
                                   its package, why that package is installed
                                   (you, or which program needed it), who
                                   started it (a service, Hyprland at login,
                                   a shortcut, D-Bus, another program)
    yakushi-taskctl.py end <pid> <start>     ask it to quit (SIGTERM), wait 3 s
    yakushi-taskctl.py force <pid> <start>   stop it at once (SIGKILL)
    yakushi-taskctl.py cont <pid> <start>    let a stopped process go on
    yakushi-taskctl.py stop-unit <unit> user|system   stop a service

<start> is the process start time from `stream`: if the PID now belongs to
another process (PIDs are reused), nothing is sent. Processes of other users
(root) are ended through pkexec, which asks for your password.

Flags: "anr" (Hyprland's "not responding" dialog is up for its window),
"stuck" (waiting on a disk or driver for 6 s or more), "stopped" (paused),
"zombie" (ended, but its parent has not collected it) and "busy" (a full
CPU core for 20 s or more - often fine: a game, a build).

Everything is read from /proc, the pacman database in /var/lib/pacman,
systemd and your Hyprland config. Nothing is downloaded.
"""
from __future__ import annotations

import json
import os
import re
import signal
import socket
import sys
import time
from pathlib import Path

HOME = Path.home()
ME = os.getuid()
PAGE = os.sysconf("SC_PAGE_SIZE")
TICK = os.sysconf("SC_CLK_TCK")
NCPU = os.cpu_count() or 1
LOCAL_DB = Path(os.environ.get("YAKUSHI_PACMAN_DB", "/var/lib/pacman/local"))
INTERPRETERS = re.compile(r"^(python[\d.]*|perl[\d.]*|ruby[\d.]*|node|nodejs|bash|sh|dash|zsh|fish|lua[\d.]*|luajit|gjs|qs|quickshell)$")

# Yakushi's own parts, recognised by a file in the command line
YAKUSHI_PARTS = {
    "topbar-shell.qml": "Yakushi top bar",
    "settings-shell.qml": "Yakushi Settings (this window)",
    "volume-osd-shell.qml": "Yakushi volume pop-up",
    "wallpicker": "Yakushi wallpaper picker",
    "yakushi-shake.py": "Yakushi shake to find",
    "yakushi-taskctl.py": "Yakushi Tasks helper (this page)",
}


# ---- small readers -----------------------------------------------------------------
def read(path, default: str = "") -> str:
    try:
        with open(path, "r", errors="replace") as f:
            return f.read()
    except OSError:
        return default


def cmdline(pid: int) -> list[str]:
    raw = read(f"/proc/{pid}/cmdline")
    return [a for a in raw.split("\0") if a] if raw else []


def stat(pid: int) -> dict | None:
    raw = read(f"/proc/{pid}/stat")
    if not raw:
        return None
    try:
        comm = raw[raw.index("(") + 1:raw.rindex(")")]
        f = raw[raw.rindex(")") + 2:].split()
        return {
            "comm": comm,
            "state": f[0],
            "ppid": int(f[1]),
            "time": int(f[11]) + int(f[12]),        # utime + stime
            "threads": int(f[17]),
            "start": int(f[19]),
            "rss": int(f[21]) * PAGE,
        }
    except (ValueError, IndexError):
        return None


def uid_of(pid: int) -> int:
    try:
        return os.stat(f"/proc/{pid}").st_uid
    except OSError:
        return -1


_users: dict[int, str] = {}


def user_name(uid: int) -> str:
    if uid not in _users:
        try:
            import pwd
            _users[uid] = pwd.getpwuid(uid).pw_name
        except (KeyError, ImportError):
            _users[uid] = str(uid)
    return _users[uid]


def script_of(argv: list[str]) -> str:
    """the script an interpreter runs (python3 foo.py -> foo.py), else ''"""
    if not argv or not INTERPRETERS.match(os.path.basename(argv[0])):
        return ""
    args = argv[1:]
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-c", "-m", "-e", "-C"):          # inline code / a module: no file
            return ""
        if a in ("-p", "--path"):                  # qs -p <file>
            return args[i + 1] if i + 1 < len(args) else ""
        if a in ("-W", "-X"):                      # options with a value
            i += 2
            continue
        if not a.startswith("-"):
            return a
        i += 1
    return ""


def display_name(comm: str, argv: list[str]) -> str:
    script = script_of(argv)
    if script:
        for key, label in YAKUSHI_PARTS.items():
            if key in script:
                return label
        return os.path.basename(script.rstrip("/"))
    if argv:
        base = os.path.basename(argv[0].split(" ")[0])
        if base and len(base) >= len(comm):
            return base
    return comm


# ---- .desktop names: "firefox" -> "Firefox" ---------------------------------------
def desktop_names() -> dict[str, str]:
    data = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    dirs = [HOME / ".local/share/applications"] + [Path(d) / "applications" for d in data if d]
    names: dict[str, str] = {}
    for d in reversed(dirs):                         # user entries win
        try:
            entries = list(d.glob("*.desktop"))
        except OSError:
            continue
        for p in entries:
            text = read(p)
            name = re.search(r"^Name=(.+)$", text, re.M)
            exe = re.search(r"^Exec=(.+)$", text, re.M)
            if not name or not exe or re.search(r"^NoDisplay=true", text, re.M):
                continue
            words = [w for w in exe.group(1).split() if "=" not in w and w not in ("env", "flatpak", "run")]
            if words:
                names[os.path.basename(words[0].strip('"'))] = name.group(1).strip()
    return names


# ---- Hyprland windows ---------------------------------------------------------------
def hypr_windows() -> dict[int, tuple[str, str]]:
    """pid -> (window title, class), read straight from Hyprland's socket"""
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    run = os.environ.get("XDG_RUNTIME_DIR")
    if not sig or not run:
        return {}
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect(f"{run}/hypr/{sig}/.socket.sock")
            s.sendall(b"j/clients")
            data = b""
            while True:
                part = s.recv(65536)
                if not part:
                    break
                data += part
        out = {}
        for c in json.loads(data.decode(errors="replace")):
            if c.get("pid", -1) > 0:
                out.setdefault(int(c["pid"]), (c.get("title") or c.get("class") or "", c.get("class") or ""))
        return out
    except (OSError, ValueError):
        return {}


# ---- stream ---------------------------------------------------------------------------
def cpu_total() -> int:
    line = read("/proc/stat").split("\n", 1)[0].split()
    return sum(int(x) for x in line[1:9]) if line and line[0] == "cpu" else 0


def cpu_idle() -> int:
    line = read("/proc/stat").split("\n", 1)[0].split()
    return int(line[4]) + int(line[5]) if len(line) > 5 else 0


def memory() -> tuple[int, int]:
    info = {}
    for line in read("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        info[k] = int(v.split()[0]) * 1024 if v.split() else 0
    total = info.get("MemTotal", 0)
    return total - info.get("MemAvailable", 0), total


def stream() -> None:
    parent = os.getppid()
    names = desktop_names()
    seen: dict[tuple[int, int], dict] = {}          # (pid, start) -> fixed facts
    last_time: dict[int, int] = {}
    last_total, last_idle = cpu_total(), cpu_idle()
    windows: dict[int, tuple[str, str]] = {}
    stuck_since: dict[int, float] = {}
    busy_since: dict[int, float] = {}
    tick = 0
    time.sleep(0.5)
    while True:
        if os.getppid() != parent:                   # Settings is gone
            return
        if tick % 2 == 0:
            windows = hypr_windows()
        total, idle = cpu_total(), cpu_idle()
        span = max(1, total - last_total)
        busy = 100.0 * (1 - (idle - last_idle) / span)
        last_total, last_idle = total, idle

        procs = []
        times: dict[int, int] = {}
        dialogs: list[str] = []                       # text of Hyprland's "not responding" dialogs
        now = time.monotonic()
        for entry in os.scandir("/proc"):
            if not entry.name.isdigit():
                continue
            pid = int(entry.name)
            st = stat(pid)
            if st is None or st["ppid"] == 2 or pid == 2:      # kernel threads
                continue
            key = (pid, st["start"])
            fixed = seen.get(key)
            if fixed is None:
                argv = cmdline(pid)
                uid = uid_of(pid)
                name = display_name(st["comm"], argv)
                fixed = {
                    "name": names.get(os.path.basename(argv[0]) if argv else "", name) if not script_of(argv) else name,
                    "proc": st["comm"],
                    "user": user_name(uid),
                    "mine": uid == ME,
                    "cmd": " ".join(argv)[:300],
                }
                seen[key] = fixed
            times[pid] = st["time"]
            cpu = 100.0 * (st["time"] - last_time.get(pid, st["time"])) / span
            if st["comm"].startswith("hyprland-dialo"):
                dialogs.append(" ".join(cmdline(pid)))
            state = st["state"]
            if state == "D":
                stuck_since.setdefault(pid, now)
            else:
                stuck_since.pop(pid, None)
            if cpu * NCPU >= 90:
                busy_since.setdefault(pid, now)
            else:
                busy_since.pop(pid, None)
            flag = ("stopped" if state in ("T", "t") else "zombie" if state == "Z"
                    else "stuck" if now - stuck_since.get(pid, now) >= 6
                    else "busy" if now - busy_since.get(pid, now) >= 20 else "")
            win = windows.get(pid, ("", ""))
            procs.append({
                "pid": pid, "ppid": st["ppid"], "name": fixed["name"], "proc": fixed["proc"],
                "user": fixed["user"], "mine": fixed["mine"], "cmd": fixed["cmd"],
                "cpu": round(cpu, 1), "mem": st["rss"], "state": state, "threads": st["threads"],
                "window": win[0], "start": st["start"], "flag": flag,
                "_class": win[1],
            })
        # Hyprland pings every window; when one stops answering it opens
        # hyprland-dialog with the window's title and class in the text
        for p in procs:
            cls = p.pop("_class")
            if dialogs and p["window"] and any(p["window"] in d or (cls and cls in d) for d in dialogs):
                p["flag"] = "anr"
        for gone in set(stuck_since) - set(times):
            stuck_since.pop(gone, None)
        for gone in set(busy_since) - set(times):
            busy_since.pop(gone, None)
        last_time = times
        if len(seen) > 4 * max(len(procs), 100):               # forget old processes
            live = {(p["pid"]) for p in procs}
            seen = {k: v for k, v in seen.items() if k[0] in live}
        used, mem_total = memory()
        try:
            sys.stdout.write(json.dumps({"cpu": round(busy, 1), "memUsed": used, "memTotal": mem_total,
                                         "cores": NCPU, "procs": procs}, separators=(",", ":")) + "\n")
            sys.stdout.flush()
        except (BrokenPipeError, OSError):
            return
        tick += 1
        time.sleep(1.5)


# ---- the pacman database ------------------------------------------------------------
def strip_version(dep: str) -> str:
    return re.split(r"[<>=:]", dep.strip(), maxsplit=1)[0].strip()


def load_packages() -> dict[str, dict]:
    pkgs: dict[str, dict] = {}
    try:
        folders = list(LOCAL_DB.iterdir())
    except OSError:
        return pkgs
    for folder in folders:
        text = read(folder / "desc")
        if not text:
            continue
        fields: dict[str, list[str]] = {}
        for block in text.split("\n\n"):
            lines = block.strip().split("\n")
            if lines and lines[0].startswith("%") and lines[0].endswith("%"):
                fields[lines[0].strip("%")] = lines[1:]
        name = (fields.get("NAME") or [""])[0]
        if not name:
            continue
        pkgs[name] = {
            "name": name,
            "version": (fields.get("VERSION") or [""])[0],
            "desc": (fields.get("DESC") or [""])[0],
            "url": (fields.get("URL") or [""])[0],
            "explicit": (fields.get("REASON") or ["0"])[0] != "1",
            "installed": int((fields.get("INSTALLDATE") or ["0"])[0] or 0),
            "size": int((fields.get("SIZE") or ["0"])[0] or 0),
            "depends": [strip_version(d) for d in fields.get("DEPENDS", [])],
            "optdepends": [strip_version(d.split(":", 1)[0]) for d in fields.get("OPTDEPENDS", [])],
            "provides": [strip_version(d) for d in fields.get("PROVIDES", [])],
            "groups": fields.get("GROUPS", []),
        }
    return pkgs


def reverse_deps(pkgs: dict[str, dict]) -> tuple[dict[str, list[str]], dict[str, list[str]]]:
    provider = {}
    for p in pkgs.values():
        for prov in p["provides"]:
            provider.setdefault(prov, p["name"])
    required_by: dict[str, list[str]] = {}
    optional_for: dict[str, list[str]] = {}
    for p in pkgs.values():
        for dep in p["depends"]:
            target = dep if dep in pkgs else provider.get(dep)
            if target and target != p["name"]:
                required_by.setdefault(target, []).append(p["name"])
        for dep in p["optdepends"]:
            target = dep if dep in pkgs else provider.get(dep)
            if target and target != p["name"]:
                optional_for.setdefault(target, []).append(p["name"])
    return required_by, optional_for


def roots(pkg: str, pkgs: dict, required_by: dict, limit: int = 3) -> list[list[str]]:
    """shortest chains pkg <- ... <- a package you installed yourself"""
    found: list[list[str]] = []
    seen = {pkg}
    queue = [[pkg]]
    while queue and len(found) < limit:
        nxt = []
        for chain in queue:
            for parent in sorted(required_by.get(chain[-1], [])):
                if parent in seen:
                    continue
                seen.add(parent)
                path = chain + [parent]
                if pkgs[parent]["explicit"]:
                    found.append(path)
                    if len(found) >= limit:
                        break
                else:
                    nxt.append(path)
            if len(found) >= limit:
                break
        queue = nxt
    return found


def owner(path: str) -> str:
    """the package that owns a file (pacman -Qqo), '' if none"""
    if not path or not os.path.isabs(path):
        return ""
    import subprocess
    try:
        res = subprocess.run(["pacman", "-Qqo", path], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return res.stdout.strip().splitlines()[0] if res.returncode == 0 and res.stdout.strip() else ""


# ---- systemd and D-Bus --------------------------------------------------------------
def unit_of(pid: int) -> tuple[str, bool]:
    """(unit, is a user unit) from /proc/<pid>/cgroup"""
    for line in read(f"/proc/{pid}/cgroup").splitlines():
        path = line.split(":", 2)[-1]
        if not path or path == "/":
            continue
        parts = [p for p in path.split("/") if p]
        user = any(p.startswith("user@") for p in parts)
        for p in reversed(parts):
            if p.endswith((".service", ".scope")) and not p.startswith("user@"):
                return p, user
        return "", user
    return "", False


def unit_info(unit: str, user: bool) -> dict:
    import subprocess
    cmd = ["systemctl"] + (["--user"] if user else []) + [
        "show", "-p", "Description,UnitFileState,FragmentPath,TriggeredBy,WantedBy", "--", unit]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return {}
    out = {}
    for line in res.stdout.splitlines():
        k, _, v = line.partition("=")
        out[k] = v
    return out


def dbus_name(exe: str) -> str:
    """the D-Bus name whose service file starts this program"""
    if not exe:
        return ""
    for d in ("/usr/share/dbus-1/services", "/usr/share/dbus-1/system-services", str(HOME / ".local/share/dbus-1/services")):
        try:
            files = list(Path(d).glob("*.service"))
        except OSError:
            continue
        for f in files:
            text = read(f)
            m = re.search(r"^Exec=(\S+)", text, re.M)
            n = re.search(r"^Name=(\S+)", text, re.M)
            if m and n and os.path.basename(m.group(1)) == os.path.basename(exe):
                return n.group(1)
    return ""


# ---- Hyprland config: autostart and shortcuts ----------------------------------------
def hypr_mentions(words: list[str]) -> tuple[str, str]:
    """(autostart line, shortcut description) that start one of these words"""
    words = [w for w in words if w and len(w) > 2]
    pats = [re.compile(r'(^|[\s/"\'])' + re.escape(w) + r'($|[\s"\'])') for w in words]

    def hit(line: str) -> bool:
        return any(p.search(line) for p in pats)

    start, bind = "", ""
    lua = read(HOME / ".config/hypr/hyprland.lua")
    block = re.search(r"startup\s*=\s*\{(.*?)\n\}", lua, re.S)
    for line in (block.group(1) if block else lua).splitlines():
        if '"' in line and hit(line.split("--", 1)[0]):
            quoted = re.search(r'"([^"]+)"', line)
            start = quoted.group(1) if quoted else line.strip().rstrip(",")
            break
    keys = read(HOME / ".config/hypr/keybinds.lua").splitlines()
    for i, line in enumerate(keys):
        m = re.match(r'\s*yakushi_bind\("[^"]+",\s*"([^"]+)"', line)
        if m and hit(line):
            label = ""
            if i and "YAKUSHI_BIND" in keys[i - 1]:
                label = keys[i - 1].split("|")[2].strip() if keys[i - 1].count("|") >= 2 else ""
            bind = m.group(1) + (f" ({label})" if label else "")
            break
    return start, bind


# ---- why ------------------------------------------------------------------------------
def ago(seconds: float) -> str:
    s = max(0, int(seconds))
    if s < 90:
        return f"{s} s ago"
    if s < 5400:
        return f"{s // 60} min ago"
    if s < 172800:
        return f"{s // 3600} h ago"
    return f"{s // 86400} days ago"


def why(pid: int) -> dict:
    st = stat(pid)
    if st is None:
        return {"ok": False, "message": "That process has ended."}
    argv = cmdline(pid)
    try:
        exe = os.readlink(f"/proc/{pid}/exe").removesuffix(" (deleted)")
    except OSError:
        exe = ""
    script = script_of(argv)
    if script and not os.path.isabs(script):
        cwd = ""
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
        except OSError:
            pass
        script = os.path.normpath(os.path.join(cwd, script)) if cwd else script
    uptime = float(read("/proc/uptime", "0").split()[0] or 0)
    started = uptime - st["start"] / TICK
    uid = uid_of(pid)
    name = display_name(st["comm"], argv)

    # parent chain, up to (not including) systemd / init
    chain = []
    p = st["ppid"]
    while p > 1 and len(chain) < 8:
        ps = stat(p)
        if ps is None:
            break
        chain.append({"pid": p, "name": display_name(ps["comm"], cmdline(p))})
        p = ps["ppid"]

    facts = {
        "pid": pid, "name": name, "proc": st["comm"], "state": st["state"], "threads": st["threads"],
        "user": user_name(uid), "started": ago(started), "memory": st["rss"],
        "command": " ".join(argv), "program": exe, "script": script,
        "parents": chain, "start": st["start"],
    }
    lines: list[dict] = []       # {"kind": ..., "text": ...}, most telling first

    # -- a kernel thread / no program file
    if st["ppid"] == 2 or pid == 2:
        lines.append({"kind": "kernel", "text": "A worker of the Linux kernel itself. It is not a program you can remove."})
        return {"ok": True, "facts": facts, "lines": lines, "package": None,
                "guard": {"level": "none", "text": "Part of the kernel: it cannot be ended."}, "unit": None, "other": True}

    # -- Flatpak apps live in their own sandbox: app-flatpak-<id>-<n>.scope
    fp = re.search(r"app-flatpak-([A-Za-z0-9_.-]+?)-\d+\.scope", read(f"/proc/{pid}/cgroup"))
    flatpak_id = fp.group(1) if fp else ""
    if flatpak_id:                  # the sandbox (bwrap) and the app id are not "who started it"
        chain = [c for c in chain if c["name"] not in ("bwrap", flatpak_id) and not c["name"].startswith("flatpak")]
        facts["parents"] = chain

    # -- which file decides the package: the script if an interpreter runs one
    target = script if script and os.path.exists(script) else exe
    yakushi = next((label for key, label in YAKUSHI_PARTS.items() if key in " ".join(argv)), "")
    home_file = target.startswith(str(HOME) + "/")

    pkgs = load_packages()
    pkg_name = owner(target) if pkgs else ""
    if not pkg_name and target != exe:
        runner = owner(exe)
    else:
        runner = ""
    package = None
    if pkg_name and pkg_name in pkgs:
        required_by, optional_for = reverse_deps(pkgs)
        info = pkgs[pkg_name]
        package = {
            "name": pkg_name, "version": info["version"], "desc": info["desc"], "url": info["url"],
            "explicit": info["explicit"], "size": info["size"],
            "requiredBy": sorted(required_by.get(pkg_name, [])),
            "optionalFor": sorted(optional_for.get(pkg_name, [])),
            "chains": [] if info["explicit"] else roots(pkg_name, pkgs, required_by),
            "groups": info["groups"],
        }
        what = f"{pkg_name} — {info['desc']}" if info["desc"] else pkg_name
        lines.append({"kind": "package", "text": f"Comes from the package {what}."})
        if info["explicit"]:
            lines.append({"kind": "reason", "text": "You installed this package yourself (or the Yakushi installer did)."})
        elif package["chains"]:
            tops = []
            for c in package["chains"]:
                if c[-1] not in tops:
                    tops.append(c[-1])
            lines.append({"kind": "reason",
                          "text": "You did not install it yourself: it came with "
                                  + " and ".join(tops) + (", which you installed." if len(tops) == 1 else ", which you installed.")
                                  + " Chain: " + ";  ".join(" ← ".join(c) for c in package["chains"]) + "."})
        elif package["requiredBy"]:
            lines.append({"kind": "reason", "text": "Installed as a dependency of " + ", ".join(package["requiredBy"][:5]) + "."})
        elif package["optionalFor"]:
            lines.append({"kind": "reason", "text": "Installed as a dependency. Nothing requires it now, but it adds features to "
                                                    + ", ".join(package["optionalFor"][:5]) + "."})
        else:
            lines.append({"kind": "reason", "text": "Installed as a dependency, but nothing needs it any more (an orphan)."})
        if "base" in info["groups"] or pkg_name in ("systemd", "linux", "glibc", "dbus", "dbus-broker"):
            lines.append({"kind": "core", "text": "Part of the base system: Linux needs it."})
    elif yakushi or (home_file and "/.config/" in target):
        lines.append({"kind": "yakushi" if yakushi else "home",
                      "text": (f"{yakushi}: part of your Yakushi setup" if yakushi else "A script in your config folder")
                              + f" ({target.replace(str(HOME), '~')})."
                              + (f" It runs with {runner}." if runner else "")})
    elif target:
        where = target.replace(str(HOME), "~")
        lines.append({"kind": "nopackage",
                      "text": (f"A Flatpak app ({flatpak_id}): it was installed with Flatpak, not pacman, "
                               "and runs in Flatpak's sandbox." if flatpak_id
                               else "A Flatpak app." if "/app/" in target
                               else f"Not from a pacman package: {where}.")
                              + (f" It runs with {runner}." if runner and not flatpak_id else "")})

    # -- who started it
    unit, user_unit = unit_of(pid)
    # the script decides if there is one (python3 alone would match too much)
    words = [os.path.basename(script)] if script else [os.path.basename(exe), st["comm"]]
    start_line, bind = hypr_mentions(words)
    started_by = ""
    if unit.endswith(".service") and not unit.startswith(("dbus", "session-")):
        ui = unit_info(unit, user_unit)
        desc = ui.get("Description", "")
        kind = "user service" if user_unit else "system service"
        text = f"Started by systemd as the {kind} {unit}" + (f" ({desc})" if desc and desc != unit else "") + "."
        state = ui.get("UnitFileState", "")
        if state == "enabled":
            text += " It is enabled, so it starts at every boot." if not user_unit else " It is enabled, so it starts with your session."
        elif ui.get("TriggeredBy"):
            text += " It starts on demand, when " + ui["TriggeredBy"].split()[0] + " is used."
        elif state in ("static", "indirect", "") and ui.get("FragmentPath"):
            text += " Another unit pulls it in when needed."
        started_by = text
    elif unit.startswith("dbus") or (unit.endswith(".service") and "dbus" in unit):
        name_on_bus = dbus_name(exe)
        started_by = ("Started on demand through D-Bus" + (f" as {name_on_bus}" if name_on_bus else "")
                      + ": another program asked for it, and it stops when nothing needs it.")
    elif start_line:
        started_by = "Hyprland starts it when you log in (hyprland.lua: " + start_line + ")."
    elif bind:
        started_by = f"Started by a shortcut: {bind}."
    if not started_by and flatpak_id and not chain:
        started_by = "Started through Flatpak."
    if not started_by and chain and chain[0]["name"] == name:
        # a helper process of the same app (browsers, Electron apps...)
        main = chain[0]
        for c in chain:
            if c["name"] != name:
                break
            main = c
        started_by = f"Part of {name}: one of its helper processes. The main one is PID {main['pid']}."
        rest = [c for c in chain if c["name"] != name]
        if flatpak_id and not rest:
            started_by += " It was started through Flatpak."
        elif rest:
            started_by += f" {name} was started by {rest[0]['name']}."
    if not started_by and chain:
        top = chain[0]["name"]
        started_by = f"Started by {top} (pid {chain[0]['pid']})."
        if len(chain) > 1:
            started_by += " Chain: " + " ← ".join(c["name"] for c in chain[:5]) + "."
    if not started_by and unit.startswith("session-"):
        started_by = "Part of your login session."
    if started_by:
        lines.append({"kind": "start", "text": started_by})
    if bind and not started_by.startswith("Started by a shortcut"):
        lines.append({"kind": "start", "text": f"A shortcut also starts it: {bind}."})
    title = windows_for(pid)
    if title:
        lines.append({"kind": "window", "text": "It has a window open: " + title + "."})
    service = None
    if unit.endswith(".service") and not unit.startswith(("dbus", "session-")) and "dbus-:" not in unit:
        service = {"name": unit, "user": user_unit}
    return {"ok": True, "facts": facts, "lines": lines, "package": package,
            "guard": guard(pid, st, argv, uid), "unit": service, "other": uid != ME}


# ---- ending things -------------------------------------------------------------------
SYSTEM_CRITICAL = re.compile(r"^(systemd(-.*)?|dbus-.*|polkitd|udevd|systemd-udevd|agetty|login|sddm(-helper)?|"
                             r"Xorg|NetworkManager|wpa_supplicant|iwd)$")


def guard(pid: int, st: dict, argv: list[str], uid: int) -> dict:
    """how careful the page must be before ending this process"""
    comm, cmd = st["comm"], " ".join(argv)
    if pid == 1:
        return {"level": "none", "text": "The first process of the system: everything runs under it."}
    if st["state"] == "Z":
        parent = stat(st["ppid"])
        who = f"{parent['comm']} (PID {st['ppid']})" if parent else f"PID {st['ppid']}"
        return {"level": "none", "text": f"It has already ended. It disappears when {who} collects it; ending {who} clears it too."}
    if comm == "Hyprland":
        return {"level": "session", "text": "Ending Hyprland logs you out: every app closes and unsaved work is lost."}
    if comm == "Xwayland":
        return {"level": "session", "text": "X11 apps (Steam, many games, some older apps) close with it."}
    if comm == "systemd" and uid == ME:
        return {"level": "session", "text": "Your session's service manager: ending it logs you out."}
    if "settings-shell.qml" in cmd or "yakushi-taskctl.py" in cmd:
        return {"level": "self", "text": "This is Settings itself: it closes."}
    if SYSTEM_CRITICAL.match(comm) and uid != ME:
        return {"level": "system", "text": "Linux needs this. Ending it can cut the network, freeze the screen or crash the system."}
    return {"level": "", "text": ""}


def alive(pid: int, start: int) -> bool:
    st = stat(pid)
    return st is not None and st["start"] == start and st["state"] != "Z"


def send(pid: int, start: int, sig: int) -> str:
    """'' when sent, else why not"""
    st = stat(pid)
    if st is None or st["start"] != start:
        return "gone"
    try:
        os.kill(pid, sig)
        return ""
    except ProcessLookupError:
        return "gone"
    except PermissionError:
        import subprocess
        name = signal.Signals(sig).name.removeprefix("SIG")
        try:
            res = subprocess.run(["pkexec", "/usr/bin/kill", "-" + name, str(pid)],
                                 capture_output=True, text=True, timeout=120)
        except (OSError, subprocess.TimeoutExpired):
            return "denied"
        return "" if res.returncode == 0 else "denied"


def end(pid: int, start: int, sig: int, wait: float) -> dict:
    why_not = send(pid, start, sig)
    if why_not == "gone":
        return {"ok": True, "gone": True, "message": "It had already ended."}
    if why_not == "denied":
        return {"ok": False, "gone": False, "message": "Not allowed: it belongs to another user and the password was not given."}
    deadline = time.monotonic() + wait
    while time.monotonic() < deadline:
        if not alive(pid, start):
            return {"ok": True, "gone": True,
                    "message": "Closed." if sig == signal.SIGTERM else "Stopped."}
        time.sleep(0.1)
    if sig == signal.SIGTERM:
        return {"ok": True, "gone": False,
                "message": "It is still running: it did not answer. FORCE END stops it at once (unsaved work in it is lost)."}
    st = stat(pid)
    if st and st["state"] == "D":
        return {"ok": False, "gone": False,
                "message": "It is waiting on the kernel (a disk or a driver) and cannot be stopped until that returns."}
    return {"ok": False, "gone": False, "message": "It did not stop."}


def go_on(pid: int, start: int) -> dict:
    why_not = send(pid, start, signal.SIGCONT)
    if why_not == "gone":
        return {"ok": True, "gone": True, "message": "It had already ended."}
    if why_not == "denied":
        return {"ok": False, "gone": False, "message": "Not allowed: the password was not given."}
    return {"ok": True, "gone": False, "message": "It goes on."}


def stop_unit(unit: str, user: bool) -> dict:
    import subprocess
    if not re.fullmatch(r"[\w@:.\-\\]+\.service", unit):
        return {"ok": False, "message": "Not a service name."}
    cmd = ["systemctl"] + (["--user"] if user else []) + ["stop", unit]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return {"ok": False, "message": "systemctl did not answer."}
    if res.returncode == 0:
        return {"ok": True, "message": f"Stopped {unit}. It may start again at the next boot or when something needs it."}
    err = (res.stderr or "").strip().splitlines()
    return {"ok": False, "message": err[-1] if err else f"Could not stop {unit}."}


def windows_for(pid: int) -> str:
    return hypr_windows().get(pid, ("", ""))[0]


# ---- commands ----------------------------------------------------------------------
def main() -> None:
    a = sys.argv[1:]
    if a == ["stream"]:
        try:
            stream()
        except KeyboardInterrupt:
            pass
    elif len(a) == 2 and a[0] == "why" and a[1].isdigit():
        print(json.dumps(why(int(a[1]))))
    elif len(a) == 3 and a[0] in ("end", "force", "cont") and a[1].isdigit() and a[2].isdigit():
        pid, start = int(a[1]), int(a[2])
        if pid <= 1:
            print(json.dumps({"ok": False, "message": "Not this one."}))
        elif a[0] == "end":
            print(json.dumps(end(pid, start, signal.SIGTERM, 3.0)))
        elif a[0] == "force":
            print(json.dumps(end(pid, start, signal.SIGKILL, 1.5)))
        else:
            print(json.dumps(go_on(pid, start)))
    elif len(a) == 3 and a[0] == "stop-unit" and a[2] in ("user", "system"):
        print(json.dumps(stop_unit(a[1], a[2] == "user")))
    else:
        print(json.dumps({"ok": False, "message": "usage: stream | why <pid> | end|force|cont <pid> <start> | "
                                                  "stop-unit <unit> user|system"}))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
