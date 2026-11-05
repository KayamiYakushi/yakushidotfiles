#!/usr/bin/env python3
"""Keeping this computer safe, without anything running in the background.
Used by Settings -> Security, and once at login.

    yakushi-securityctl.py status           the shield: firewall, what is reachable from
                                            outside, SSH, updates, auto lock, disk
                                            encryption, Secure Boot - and the guard's news
    yakushi-securityctl.py updates          look for updates and known security holes
                                            (checkupdates + arch-audit; needs the internet)
    yakushi-securityctl.py login            at login: the guard check, the update check
                                            (at most once a day), auto lock; a Hyprland
                                            notification only when something is serious
    yakushi-securityctl.py guard            the guard check now
    yakushi-securityctl.py accept <key>|all "that was me": take changes into the baseline
    yakushi-securityctl.py firewall on|off  * ufw: block everything coming in, allow going out
    yakushi-securityctl.py ssh off          * stop and disable the SSH server
    yakushi-securityctl.py autolock <min>|off   lock after <min> idle minutes and before
                                            sleep (hypridle, with its own config;
                                            * the first time, to install it)
    yakushi-securityctl.py upgrade          * the system update (pacman -Syu), right in Settings:
                                            one JSON line per step, then {"done": ...}.
                                            pacman runs on its own: closing Settings never
                                            stops it halfway
    yakushi-securityctl.py follow           watch an update that is already running
    yakushi-securityctl.py scan             * compare every system file with its package
                                            (pacman -Qkk; a few minutes)

* needs your password: --password-stdin and the first line of stdin (Settings
  asks for it in the page; it goes to sudo through a pipe), else pkexec asks.

The guard keeps a fingerprint of the places an intruder changes to stay
(what starts at login, services and timers, users and the wheel group, SSH
keys, shell start files, /etc/ld.so.preload, pacman.conf, open ports) and
says what changed since you last accepted it, plus failed logins and sudo
use from the journal. State: ~/.local/state/yakushi/security.json (only you
can read it).
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOME = Path.home()
STATE = HOME / ".local/state/yakushi/security.json"
IDLE_CONF = HOME / ".local/state/yakushi/hypridle.conf"   # its own file: yours stays yours
DAY = 20 * 3600                     # "once a day", with some room

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location("yakushi_taskctl", HERE / "yakushi-taskctl.py")
tasks = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tasks)


def emit(obj: dict) -> None:
    print(json.dumps(obj))


def run(cmd: list[str], timeout: int = 60, env: dict | None = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env)
    except FileNotFoundError:
        return subprocess.CompletedProcess(cmd, 127, "", f"{cmd[0]} is not installed")
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, "", f"{cmd[0]} took too long")


def have(tool: str) -> bool:
    return shutil.which(tool) is not None


def load() -> dict:
    try:
        data = json.loads(STATE.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save(data: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=1))
    os.chmod(tmp, 0o600)
    tmp.replace(STATE)


def read(path) -> str:
    return tasks.read(path)


def unit_state(unit: str) -> tuple[str, str]:
    a = run(["systemctl", "is-active", unit], 10).stdout.strip()
    e = run(["systemctl", "is-enabled", unit], 10).stdout.strip()
    return a, e


# ---- the shield -------------------------------------------------------------------------
def firewall() -> dict:
    ufw_on = re.search(r"^\s*ENABLED\s*=\s*yes", read("/etc/ufw/ufw.conf"), re.M | re.I) is not None
    ufw_active, _ = unit_state("ufw.service")
    if have("ufw") and ufw_on and ufw_active == "active":
        return {"on": True, "tool": "ufw", "text": "On (ufw): connections from outside are blocked unless you allowed them."}
    for unit, label in (("firewalld.service", "firewalld"), ("nftables.service", "nftables rules")):
        if unit_state(unit)[0] == "active":
            return {"on": True, "tool": label, "text": f"On ({label})."}
    if have("ufw"):
        return {"on": False, "tool": "ufw", "text": "Off: anything that listens can be reached from your network."}
    return {"on": False, "tool": "", "text": "No firewall is installed. TURN ON installs ufw (official repository)."}


LOCAL = re.compile(r"^(127\.|\[?::1\]?|localhost|\[?::ffff:127\.)")


def listening() -> list[dict]:
    """sockets open to the network (not only to this computer)"""
    res = run(["ss", "-tulnpH"], 10)
    out = []
    for line in res.stdout.splitlines():
        p = line.split()
        if len(p) < 5:
            continue
        proto, local = p[0], p[4]
        addr, _, port = local.rpartition(":")
        addr = addr.split("%")[0]
        if LOCAL.match(addr):
            continue
        prog = re.search(r'users:\(\("([^"]+)",pid=(\d+)', line)
        key = f"{proto}:{port}"
        if any(o["key"] == key for o in out):
            continue
        out.append({"key": key, "proto": proto, "port": port, "address": addr or "*",
                    "program": prog.group(1) if prog else "", "pid": int(prog.group(2)) if prog else 0})
    return sorted(out, key=lambda o: (o["proto"], int(o["port"]) if o["port"].isdigit() else 0))


def ssh_server() -> dict:
    active, enabled = unit_state("sshd.service")
    return {"active": active == "active", "enabled": enabled == "enabled", "installed": have("sshd") or Path("/usr/bin/sshd").exists()}


def encrypted_root() -> dict:
    res = run(["lsblk", "-J", "-o", "NAME,TYPE,MOUNTPOINTS"], 10)
    try:
        tree = json.loads(res.stdout).get("blockdevices", [])
    except ValueError:
        return {"known": False, "on": False}

    def walk(nodes, chain):
        for n in nodes or []:
            here = chain + [n.get("type", "")]
            if "/" in (n.get("mountpoints") or []):
                return here
            found = walk(n.get("children"), here)
            if found:
                return found
        return None
    chain = walk(tree, [])
    if chain is None:
        return {"known": False, "on": False}
    return {"known": True, "on": "crypt" in chain}


def secure_boot() -> dict:
    if not Path("/sys/firmware/efi").exists():
        return {"known": True, "efi": False, "on": False}
    try:
        data = Path("/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c").read_bytes()
        return {"known": True, "efi": True, "on": data[-1] == 1}
    except OSError:
        return {"known": False, "efi": True, "on": False}


def autolock() -> dict:
    text = read(IDLE_CONF)
    m = re.search(r"^# yakushi-autolock: (\d+|off)$", text, re.M)
    minutes = m.group(1) if m else "off"
    running = run(["pgrep", "-u", str(os.getuid()), "-f", f"hypridle -c {IDLE_CONF}"], 5).returncode == 0
    return {"minutes": minutes, "installed": have("hypridle"), "running": running}


# ---- updates and known holes -------------------------------------------------------------
AUDIT = re.compile(r"^Package (\S+) is affected by (.+?)\.\s+(\w+) risk!(?:\s+Update to (\S+?)!)?", re.I)


def check_updates() -> dict:
    result = {"time": int(time.time()), "pending": [], "holes": [], "errors": []}
    if have("checkupdates"):
        # its copy of the package lists lives in ~/.cache, not in /tmp (which is
        # RAM): it stays small there, and the next check downloads only what changed
        db = HOME / ".cache/yakushi/checkup-db"
        db.mkdir(parents=True, exist_ok=True)
        res = run(["checkupdates"], 180, env={**os.environ, "CHECKUPDATES_DB": str(db)})
        if res.returncode in (0, 2):            # 2 = no updates
            for line in res.stdout.splitlines():
                p = line.split()
                if len(p) >= 4 and p[2] == "->":
                    result["pending"].append({"name": p[0], "from": p[1], "to": p[3]})
        else:
            result["errors"].append("checkupdates could not reach the mirrors")
    else:
        result["errors"].append("pacman-contrib (checkupdates) is not installed")
    if have("arch-audit"):
        res = run(["arch-audit"], 120)
        if res.returncode == 0:
            for line in res.stdout.splitlines():
                m = AUDIT.match(line.strip())
                if m:
                    cves = [c.strip() for c in re.split(r",\s*|\s+and\s+", m.group(2)) if c.strip()]
                    result["holes"].append({"name": m.group(1), "issues": cves[:6], "count": len(cves),
                                            "risk": m.group(3).lower(), "fix": m.group(4) or ""})
        else:
            result["errors"].append("arch-audit could not reach security.archlinux.org")
    else:
        result["errors"].append("arch-audit is not installed")
    return result


# ---- the guard ------------------------------------------------------------------------------
WATCHED_FILES = [
    "~/.config/fish/config.fish", "~/.bashrc", "~/.bash_profile", "~/.profile", "~/.zshrc", "~/.zprofile",
    "~/.xprofile", "~/.pam_environment", "~/.ssh/authorized_keys", "~/.ssh/rc",
    "/etc/ld.so.preload", "/etc/environment", "/etc/hosts", "/etc/pacman.conf", "/etc/shells",
]
WATCHED_DIRS = ["~/.config/fish/conf.d", "~/.config/environment.d", "~/.config/autostart",
                "~/.config/systemd/user", "/etc/xdg/autostart", "/etc/profile.d", "/etc/cron.d"]


def digest(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()[:16]
    except OSError:
        return ""


def snapshot() -> dict[str, str]:
    """key -> fingerprint of everything the guard watches"""
    snap: dict[str, str] = {}
    lua = read(HOME / ".config/hypr/hyprland.lua")
    block = re.search(r"startup\s*=\s*\{(.*?)\n\}", lua, re.S)
    for line in (block.group(1) if block else "").splitlines():
        q = re.search(r'"([^"]+)"', line.split("--", 1)[0])
        if q:
            snap["startup:" + q.group(1)] = "1"
    for scope in ("system", "user"):
        cmd = ["systemctl"] + (["--user"] if scope == "user" else []) + [
            "list-unit-files", "--state=enabled", "--no-legend", "--plain"]
        for line in run(cmd, 20).stdout.splitlines():
            name = line.split()[0] if line.split() else ""
            if name:
                snap[f"unit:{scope}:{name}"] = "1"
    for line in read("/etc/passwd").splitlines():
        p = line.split(":")
        if len(p) >= 7 and (p[2] == "0" or not p[6].endswith(("nologin", "false", "/sync", "/shutdown", "/halt"))):
            snap["user:" + p[0]] = f"uid {p[2]}, {p[6]}"
    for line in read("/etc/group").splitlines():
        p = line.split(":")
        if len(p) >= 4 and p[0] in ("wheel", "sudo", "root"):
            snap["group:" + p[0]] = p[3]
    for f in WATCHED_FILES:
        path = Path(os.path.expanduser(f))
        if path.exists():
            snap["file:" + f] = digest(path)
    for d in WATCHED_DIRS:
        folder = Path(os.path.expanduser(d))
        try:
            for entry in sorted(folder.iterdir()):
                if entry.is_file():
                    snap["file:" + f"{d}/{entry.name}"] = digest(entry)
        except OSError:
            pass
    for sock in listening():
        # by program when we can see it (apps pick new port numbers now and then),
        # else by port (system services keep theirs)
        if sock["program"]:
            snap[f"port:{sock['proto']}:{sock['program']}"] = "1"
        else:
            snap["port:" + sock["key"]] = "1"
    return snap


def describe(key: str, kind: str, value: str = "") -> str:
    what, _, rest = key.partition(":")
    verb = {"new": "New", "gone": "Removed", "changed": "Changed"}[kind]
    if what == "startup":
        return f"{verb}: Hyprland starts at login: {rest}"
    if what == "unit":
        scope, _, name = rest.partition(":")
        return f"{verb}: {'your' if scope == 'user' else 'system'} service or timer enabled: {name}"
    if what == "user":
        return f"{verb}: user account that can log in: {rest}" + (f" ({value})" if value else "")
    if what == "group":
        return f"{verb}: members of the {rest} group (they can use sudo): {value or 'none'}"
    if what == "port":
        proto, _, which = rest.partition(":")
        where = f"port {which}" if which.isdigit() else which
        return f"{verb}: listens to your network ({proto}): {where}"
    if what == "file":
        return f"{verb}: {rest}"
    return f"{verb}: {key}"


def journal_since(since: int) -> dict:
    """failed logins, sudo use and SSH logins since a time"""
    out = {"readable": True, "failed": [], "sudo": [], "ssh": []}
    res = run(["journalctl", "--since", f"@{since}", "--no-pager", "-o", "json",
               "SYSLOG_IDENTIFIER=sudo", "+", "SYSLOG_IDENTIFIER=sshd", "+", "SYSLOG_IDENTIFIER=sshd-session",
               "+", "SYSLOG_IDENTIFIER=login", "+", "SYSLOG_IDENTIFIER=su",
               "+", "SYSLOG_IDENTIFIER=unix_chkpwd", "+", "SYSLOG_IDENTIFIER=polkit-agent-helper-1",
               "+", "SYSLOG_IDENTIFIER=hyprlock", "+", "SYSLOG_IDENTIFIER=sddm-helper"], 30)
    low = res.stderr.lower()
    if "insufficient permissions" in low or "not seeing messages" in low or (res.returncode != 0 and not res.stdout):
        out["readable"] = False
        return out
    for line in res.stdout.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        msg = e.get("MESSAGE")
        if not isinstance(msg, str):
            continue
        when = int(int(e.get("__REALTIME_TIMESTAMP", "0")) / 1e6)
        who = e.get("SYSLOG_IDENTIFIER", "")
        if re.search(r"authentication failure|Failed password|incorrect password|Invalid user|FAILED LOGIN", msg, re.I):
            if any(f["time"] == when and f["by"] != who for f in out["failed"][-3:]):
                continue                    # the same try, logged twice (pam + helper)
            out["failed"].append({"time": when, "by": who, "remote": who.startswith("sshd"), "text": msg[:160]})
        elif who == "sudo" and "COMMAND=" in msg:
            out["sudo"].append({"time": when, "text": msg.split("COMMAND=", 1)[1][:160]})
        elif who.startswith("sshd") and msg.startswith("Accepted"):
            out["ssh"].append({"time": when, "text": msg[:160]})
    for k in ("failed", "sudo", "ssh"):
        out[k] = out[k][-50:]
    return out


def guard(data: dict) -> dict:
    """compare with the baseline; the first run takes the baseline"""
    now = int(time.time())
    snap = snapshot()
    base = data.get("baseline")
    if not isinstance(base, dict):
        data["baseline"] = snap
        data["changes"] = []
        data["guardTime"] = now
        data["events"] = {"readable": True, "failed": [], "sudo": [], "ssh": [], "since": now}
        return {"first": True, "changes": []}
    changes = []
    for k, v in snap.items():
        if k not in base:
            changes.append({"key": k, "kind": "new", "text": describe(k, "new", v)})
        elif base[k] != v:
            changes.append({"key": k, "kind": "changed", "text": describe(k, "changed", v)})
    for k, v in base.items():
        if k not in snap:
            changes.append({"key": k, "kind": "gone", "text": describe(k, "gone", v)})
    data["changes"] = changes
    data["current"] = snap
    since = int(data.get("events", {}).get("since") or data.get("guardTime") or now - 86400)
    # read only what is new since the last check; older ones are kept below
    ev = journal_since(max(since, int(data.get("guardTime") or since) - 5))
    old = data.get("events", {})
    for k in ("failed", "sudo", "ssh"):            # keep what was not looked at yet
        seen = {(x["time"], x["text"]) for x in old.get(k, [])}
        ev[k] = old.get(k, []) + [x for x in ev[k] if (x["time"], x["text"]) not in seen]
        ev[k] = ev[k][-50:]
    ev["since"] = since
    data["events"] = ev
    data["guardTime"] = now
    return {"first": False, "changes": changes}


def accept(data: dict, which: str) -> None:
    snap = data.get("current") or snapshot()
    base = data.get("baseline") or {}
    keys = [c["key"] for c in data.get("changes", [])] if which == "all" else [which]
    for k in keys:
        if k in snap:
            base[k] = snap[k]
        else:
            base.pop(k, None)
    data["baseline"] = base
    data["changes"] = [c for c in data.get("changes", []) if c["key"] not in keys]


def clear_events(data: dict) -> None:
    data["events"] = {"readable": data.get("events", {}).get("readable", True),
                      "failed": [], "sudo": [], "ssh": [], "since": int(time.time())}


def notify(text: str) -> None:
    """Hyprland's own notification (no notification daemon needed)"""
    if have("hyprctl"):
        run(["hyprctl", "notify", "0", "12000", "rgb(e2202f)", "fontsize:14", text], 10)


# ---- doing things as root -------------------------------------------------------------------
def root(cmd: list[str], timeout: int = 600) -> dict:
    result, err = tasks.as_root(cmd, timeout)
    if result == "ok":
        return {"ok": True}
    return {"ok": False, "wrongPassword": result == "wrong",
            "message": tasks.ROOT_MESSAGES.get(result, err or "It did not work.")}


def set_firewall(on: bool) -> dict:
    if on:
        script = ("command -v ufw >/dev/null || pacman -S --needed --noconfirm ufw || exit 3; "
                  "ufw default deny incoming && ufw default allow outgoing && ufw --force enable "
                  "&& systemctl enable --now ufw.service")
    else:
        script = "ufw disable && systemctl disable --now ufw.service"
    r = root(["/bin/sh", "-c", script])
    if r["ok"]:
        r["message"] = ("Firewall on: nothing from outside can connect unless you allow it."
                        if on else "Firewall off.")
    return r


def ssh_off() -> dict:
    r = root(["systemctl", "disable", "--now", "sshd.service", "sshd.socket"])
    if not r["ok"] and not r.get("wrongPassword") and not ssh_server()["active"]:
        r = {"ok": True}
    if r["ok"]:
        r["message"] = "The SSH server is off and will not start at boot."
    return r


def write_idle(minutes: str) -> None:
    if minutes == "off":
        text = "# yakushi-autolock: off\n# Settings -> Security -> Auto lock writes this file.\n"
    else:
        sec = int(minutes) * 60
        text = (f"# yakushi-autolock: {minutes}\n"
                "# Settings -> Security -> Auto lock writes this file.\n"
                "general {\n"
                "    lock_cmd = pidof hyprlock || hyprlock\n"
                "    before_sleep_cmd = loginctl lock-session\n"
                "}\n\n"
                "listener {\n"
                f"    timeout = {sec}\n"
                "    on-timeout = loginctl lock-session\n"
                "}\n")
    IDLE_CONF.parent.mkdir(parents=True, exist_ok=True)
    IDLE_CONF.write_text(text)


def start_idle(on: bool) -> None:
    run(["pkill", "-u", str(os.getuid()), "-f", f"hypridle -c {IDLE_CONF}"], 5)   # only ours
    if on and have("hypridle"):
        subprocess.Popen(["setsid", "hypridle", "-c", str(IDLE_CONF)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         stdin=subprocess.DEVNULL, start_new_session=True)


def set_autolock(minutes: str) -> dict:
    if minutes != "off" and not (minutes.isdigit() and 1 <= int(minutes) <= 240):
        return {"ok": False, "message": "Minutes from 1 to 240, or off."}
    if minutes != "off" and not have("hypridle"):
        r = root(["pacman", "-S", "--needed", "--noconfirm", "hypridle"])
        if not r["ok"]:
            return r
    write_idle(minutes)
    start_idle(minutes != "off")
    return {"ok": True, "message": "Auto lock off." if minutes == "off"
            else f"The screen locks after {minutes} idle minutes, and before sleep."}


# caches that pacman hooks rebuild after installs: they never match the
# package's copy, and that is how it should be
REBUILT = re.compile(r"(\.cache|/plugins\.dat|/locale-archive|/gschemas\.compiled|/mime/[^/]+|/info/dir|"
                     r"/ld\.so\.cache|/fonts\.(dir|scale)|/\.uuid)$")
SCAN_RED = re.compile(r"^warning:\s+(\S+):\s+(/.*?)\s+\(([^()]+)\)$")


def deep_scan() -> dict:
    out = tasks.PASSWORD
    cmd = ["/bin/sh", "-c", "LC_ALL=C pacman -Qkk 2>&1; exit 0"]
    if out is not None:
        res = subprocess.run(["sudo", "-S", "-k", "-p", "", "--", *cmd], input=out + "\n",
                             capture_output=True, text=True, timeout=1800)
        if res.returncode != 0 and ("incorrect password" in res.stderr or "Sorry, try again" in res.stderr):
            return {"ok": False, "wrongPassword": True, "message": tasks.ROOT_MESSAGES["wrong"]}
    else:
        res = run(["pkexec", *cmd], 1800)
        if res.returncode in (126, 127):
            return {"ok": False, "message": tasks.ROOT_MESSAGES["cancel"]}
    red, configs, other, caches = {}, 0, 0, set()
    for line in res.stdout.splitlines():
        m = SCAN_RED.match(line.strip())
        if not m:
            continue
        pkg, path, why = m.groups()
        if path.startswith("/etc/") or "backup" in why.lower():
            configs += 1                    # your own settings: changes are normal
            continue
        if REBUILT.search(path):
            caches.add(path)                # rebuilt on this computer by a pacman hook
            continue
        serious = re.search(r"checksum|size mismatch|symlink", why, re.I) and \
            re.match(r"^/(usr/(bin|sbin|lib|lib64|local/bin)|boot|bin|sbin|lib)", path)
        if serious:
            if path in red:                 # one file, several reasons: one line
                red[path]["why"] += ", " + why
            else:
                red[path] = {"package": pkg, "path": path, "why": why}
        else:
            other += 1
    red = list(red.values())
    result = {"time": int(time.time()), "red": red[:100], "redCount": len(red), "configs": configs,
              "caches": len(caches), "other": other}
    data = load()
    data["scan"] = result
    save(data)
    msg = ("No system program was changed: every one matches its package."
           if not red else f"{len(red)} system files differ from their package. Look at them below.")
    return {"ok": True, "message": msg, "scan": result}


# ---- the system update, inside Settings -----------------------------------------------------
# pacman runs detached (its own session, output into a file), so closing
# Settings or this helper can never stop it halfway. This helper only reads
# the file and tells the page how far it is.
UPDATE_LOG = STATE.parent / "update.log"
UPDATE_RUN = STATE.parent / "update.run"          # "<pid> <start>" while it runs
EXIT_MARK = "@@yakushi-exit "
PHASES = [
    (":: Synchronizing package databases", "Refreshing the package lists"),
    (":: Starting full system upgrade", "Looking for updates"),
    (":: Retrieving packages", "Downloading"),
    ("checking keyring", "Checking signatures"),
    ("checking package integrity", "Checking packages"),
    ("checking for file conflicts", "Checking packages"),
    (":: Processing package changes", "Installing"),
    (":: Running pre-transaction hooks", "Preparing"),
    (":: Running post-transaction hooks", "Finishing up"),
]


def update_pid() -> int:
    """the running update's pid, or 0"""
    try:
        pid, start = (int(x) for x in UPDATE_RUN.read_text().split()[:2])
    except (OSError, ValueError):
        return 0
    st = tasks.stat(pid)
    return pid if st is not None and st["start"] == start and st["state"] != "Z" else 0


def kernels() -> set[str]:
    out = set()
    for f in Path("/usr/lib/modules").glob("*/pkgbase"):
        name = read(f).strip()
        if name:
            out.add(name)
    return out or {"linux"}


def summary(text: str) -> dict:
    """what an update log says, in words"""
    lines = text.splitlines()
    m = [l for l in lines if l.startswith(EXIT_MARK)]
    code = int(m[-1][len(EXIT_MARK):].strip() or 1) if m else None
    if code is None and re.search(r"Sorry, try again|incorrect password|no password was provided|password is required", text):
        return {"ok": False, "wrongPassword": True, "message": tasks.ROOT_MESSAGES["wrong"]}
    upgraded = re.findall(r"^\(\s*\d+/\d+\) (?:upgrading|installing) (\S+)", text, re.M)
    pacnew = re.findall(r"installed as (\S+\.pacnew)", text)
    k = kernels()
    restart = any(u in k for u in upgraded)
    relog = not restart and any(u in ("hyprland", "systemd", "glibc", "mesa", "quickshell") for u in upgraded)
    if code == 0:
        if "there is nothing to do" in text:
            msg = "Everything was already up to date."
        else:
            msg = f"Updated {len(upgraded)} package{'s' if len(upgraded) != 1 else ''}."
            if restart:
                msg += " A new kernel is installed: restart the computer when you can."
            elif relog:
                msg += " Log out and back in when you can, so everything uses the new versions."
        if pacnew:
            msg += f" {len(pacnew)} settings file(s) got a new default next to yours (.pacnew); yours were kept."
        return {"ok": True, "message": msg, "restart": restart, "relog": relog, "pacnew": pacnew[:10]}
    errors = [l for l in lines if l.startswith("error:")]
    why = errors[-1][6:].strip() if errors else (lines[-2] if len(lines) > 1 else "")
    if code is None:
        why = why or "it stopped before finishing"
    msg = "The update did not finish: " + why
    if re.search(r"conflict|could not satisfy|breaks dependency|are in conflict", text):
        msg += ". pacman needs a decision from you: OPEN IN TERMINAL lets you answer it."
    elif "Could not resolve host" in text or "failed retrieving file" in text:
        msg += ". Check the internet connection and try again."
    return {"ok": False, "message": msg, "terminal": True}


def finish(data: dict) -> dict:
    """the update ended: remember its result"""
    result = summary(read(UPDATE_LOG))
    result["time"] = int(time.time())
    UPDATE_RUN.unlink(missing_ok=True)
    if not result.get("wrongPassword"):
        data["lastUpdate"] = result
    return result


class Progress:
    def __init__(self):
        self.phase, self.n, self.total, self.got = "Starting", 0, 0, 0

    def feed(self, line: str) -> dict | None:
        l = line.strip()
        if not l or l.startswith(EXIT_MARK):
            return None
        for head, phase in PHASES:
            if l.startswith(head):
                self.phase, self.n = phase, 0
                if phase == "Downloading":
                    self.got = 0            # the package lists before were not packages
        m = re.match(r"^Packages \((\d+)\)", l)
        if m:
            self.total = int(m.group(1))
        if l.endswith("downloading..."):
            self.phase = "Downloading"
            self.got += 1
            self.n = min(self.got, self.total) if self.total else self.got
        m = re.match(r"^\(\s*(\d+)/(\d+)\)", l)
        if m:
            self.n, self.total = int(m.group(1)), int(m.group(2))
            if self.phase == "Downloading":
                self.phase = "Installing"
        if l.startswith("there is nothing to do"):
            self.phase = "Nothing to update"
        return {"phase": self.phase, "n": self.n, "total": self.total, "line": l[:200]}


def follow(proc=None) -> None:
    prog = Progress()
    pos = 0
    tail = ""
    while True:
        try:
            with open(UPDATE_LOG, errors="replace") as f:
                f.seek(pos)
                chunk = f.read()
                pos = f.tell()
        except OSError:
            chunk = ""
        tail += chunk
        *lines, tail = tail.split("\n")
        for line in lines:
            step = prog.feed(line)
            if step:
                print(json.dumps(step), flush=True)
        alive = proc.poll() is None if proc is not None else update_pid() != 0
        if not alive and not chunk:
            break
        time.sleep(0.3)
    data = load()
    result = finish(data)
    if result.get("ok"):
        print(json.dumps({"phase": "Checking again", "n": 0, "total": 0, "line": ""}), flush=True)
        data["updates"] = check_updates()
    save(data)
    print(json.dumps({"done": True, **result}), flush=True)


def upgrade() -> None:
    if update_pid():
        return follow()
    if tasks.PASSWORD is None:
        print(json.dumps({"done": True, "ok": False, "message": "Your password is needed."}), flush=True)
        return
    if Path("/var/lib/pacman/db.lck").exists():
        busy = run(["pgrep", "-x", "pacman"], 5).returncode == 0
        print(json.dumps({"done": True, "ok": False, "terminal": not busy, "message":
              "Another install or update is running: wait for it to finish." if busy else
              "pacman's lock file was left behind by an update that did not finish "
              "(/var/lib/pacman/db.lck). If nothing else is installing, remove it: sudo rm /var/lib/pacman/db.lck"}),
              flush=True)
        return
    STATE.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(UPDATE_LOG, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    script = ("LC_ALL=C pacman -Syu --noconfirm --noprogressbar --color never; "
              f'echo "{EXIT_MARK}$?"')
    proc = subprocess.Popen(["sudo", "-S", "-k", "-p", "", "--", "/bin/sh", "-c", script],
                            stdin=subprocess.PIPE, stdout=fd, stderr=fd, start_new_session=True, text=True)
    os.close(fd)
    try:
        proc.stdin.write(tasks.PASSWORD + "\n")
        proc.stdin.close()
    except OSError:
        pass
    st = tasks.stat(proc.pid)
    if st is not None:
        UPDATE_RUN.write_text(f"{proc.pid} {st['start']}")
    follow(proc)


# ---- status ---------------------------------------------------------------------------------
def status() -> dict:
    data = load()
    if UPDATE_RUN.exists() and not update_pid():      # it ended while Settings was closed
        finish(data)
        save(data)
    return {
        "upgrading": update_pid() != 0,
        "lastUpdate": data.get("lastUpdate"),
        "ok": True,
        "firewall": firewall(),
        "listening": listening(),
        "ssh": ssh_server(),
        "updates": data.get("updates"),
        "autolock": autolock(),
        "encryption": encrypted_root(),
        "secureBoot": secure_boot(),
        "guard": {"time": data.get("guardTime"), "changes": data.get("changes", []),
                  "events": data.get("events", {}), "baseline": isinstance(data.get("baseline"), dict)},
        "scan": data.get("scan"),
        "tools": {t: have(t) for t in ("ufw", "arch-audit", "checkupdates", "hypridle", "ss")},
    }


def login() -> None:
    data = load()
    g = guard(data)
    if not data.get("updates") or int(time.time()) - int(data["updates"].get("time", 0)) > DAY:
        try:
            os.nice(10)                        # stay out of the way while you start working
        except OSError:
            pass
        data["updates"] = check_updates()
    save(data)
    if autolock()["minutes"] != "off":
        start_idle(True)
    news = []
    if g["changes"]:
        news.append(f"{len(g['changes'])} change(s) to what starts or listens on this computer")
    failed = data.get("events", {}).get("failed", [])
    remote = [f for f in failed if f.get("remote")]
    if remote:                                   # someone tried from the network
        news.append(f"{len(remote)} failed SSH login attempt(s) from the network")
    elif len(failed) >= 3:                       # one or two typos are just typos
        news.append(f"{len(failed)} failed password attempts on this computer")
    holes = [h for h in data["updates"].get("holes", []) if h.get("fix")]
    if holes:
        news.append(f"{len(holes)} package(s) with a known security hole have a fix")
    if news:
        notify("Yakushi Guard: " + "; ".join(news) + ". Open Settings -> Security (SUPER + I).")


def main() -> None:
    a = tasks.take_password(sys.argv[1:])
    try:
        if a == ["status"]:
            emit(status())
        elif a == ["updates"]:
            data = load()
            data["updates"] = check_updates()
            save(data)
            emit({"ok": True, "updates": data["updates"]})
        elif a == ["login"]:
            login()
        elif a == ["guard"]:
            data = load()
            g = guard(data)
            save(data)
            emit({"ok": True, **g})
        elif len(a) == 2 and a[0] == "accept":
            data = load()
            accept(data, a[1])
            save(data)
            emit({"ok": True, "message": "Taken as yours."})
        elif a == ["seen"]:
            data = load()
            clear_events(data)
            save(data)
            emit({"ok": True})
        elif len(a) == 2 and a[0] == "firewall" and a[1] in ("on", "off"):
            emit(set_firewall(a[1] == "on"))
        elif a == ["ssh", "off"]:
            emit(ssh_off())
        elif len(a) == 2 and a[0] == "autolock":
            emit(set_autolock(a[1]))
        elif a == ["upgrade"]:
            upgrade()
        elif a == ["follow"]:
            follow()
        elif a == ["scan"]:
            emit(deep_scan())
        else:
            emit({"ok": False, "message": "usage: status | updates | login | guard | accept <key>|all | seen | "
                                          "firewall on|off | ssh off | autolock <min>|off | scan | upgrade | follow"})
    except Exception as e:                       # always answer the page
        emit({"ok": False, "message": f"Unexpected error: {e}"})


if __name__ == "__main__":
    main()
