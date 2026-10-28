#!/usr/bin/env python3
"""Default applications for Settings -> Default Apps.

Commands:
    scan                  Installed apps per category + the current choice (JSON).
    set <category> <id>   Make the app (a .desktop id) the default for that category.
    shell <path>          Change the login shell (asks for your password via polkit).

What "default" means here:
    * Files and links open with it: ~/.config/mimeapps.list [Default Applications]
      (the same file `xdg-mime default` writes; other entries are kept).
    * Terminal, file manager and browser are also what SUPER + Q / E / B open:
      the `terminal`, `fileManager` and `browser` lines in ~/.config/hypr/hyprland.lua,
      then `hyprctl reload`. The terminal also goes first in xdg-terminals.list
      (used by xdg-terminal-exec and apps that open a terminal).

Apps are found from their .desktop files (system, ~/.local/share, Flatpak).
Runs only when called: no daemon, no timers.
"""
from __future__ import annotations

import configparser
import json
import os
import pwd
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
MIMEAPPS = CONFIG / "mimeapps.list"
HYPR_CONF = CONFIG / "hypr/hyprland.lua"
XDG_TERMINALS = CONFIG / "xdg-terminals.list"


def app_dirs() -> list[Path]:
    data_home = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
    data_dirs = [Path(p) for p in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if p]
    dirs = [data_home, data_home / "flatpak/exports/share", Path("/var/lib/flatpak/exports/share")] + data_dirs
    seen, out = set(), []
    for d in dirs:
        a = d / "applications"
        if a not in seen:
            seen.add(a)
            out.append(a)
    return out


# category: label, mime types it owns, how to recognise candidates, Hyprland variable
CATEGORIES = {
    "terminal": {
        "label": "Terminal", "mimes": [], "hypr": "terminal",
        "match": lambda e: "TerminalEmulator" in e["categories"],
    },
    "files": {
        "label": "File manager", "mimes": ["inode/directory"], "hypr": "fileManager",
        "match": lambda e: "inode/directory" in e["mimes"] or "FileManager" in e["categories"],
    },
    "browser": {
        "label": "Web browser", "hypr": "browser",
        "mimes": ["x-scheme-handler/http", "x-scheme-handler/https", "text/html",
                  "application/xhtml+xml", "x-scheme-handler/about", "x-scheme-handler/unknown"],
        "match": lambda e: "WebBrowser" in e["categories"] or "x-scheme-handler/http" in e["mimes"],
    },
    "editor": {
        "label": "Text editor", "hypr": None,
        "mimes": ["text/plain", "text/markdown", "application/x-shellscript", "text/x-python",
                  "application/json", "text/x-csrc", "text/x-c++src"],
        "match": lambda e: "text/plain" in e["mimes"] and not e["is_browser"],
    },
    "images": {
        "label": "Image viewer", "hypr": None,
        "mimes": ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/svg+xml",
                  "image/avif", "image/tiff"],
        "match": lambda e: ("image/png" in e["mimes"] or "image/jpeg" in e["mimes"]) and not e["is_browser"],
    },
    "video": {
        "label": "Video player", "hypr": None,
        "mimes": ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo",
                  "video/mpeg"],
        "match": lambda e: ("video/mp4" in e["mimes"] or "video/x-matroska" in e["mimes"]) and not e["is_browser"],
    },
    "audio": {
        "label": "Music player", "hypr": None,
        "mimes": ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav", "audio/mp4", "audio/x-opus+ogg"],
        "match": lambda e: ("audio/mpeg" in e["mimes"] or "audio/flac" in e["mimes"]) and not e["is_browser"],
    },
    "pdf": {
        "label": "PDF viewer", "hypr": None,
        "mimes": ["application/pdf"],
        "match": lambda e: "application/pdf" in e["mimes"],
    },
    "mail": {
        "label": "Email", "hypr": None,
        "mimes": ["x-scheme-handler/mailto"],
        "match": lambda e: "x-scheme-handler/mailto" in e["mimes"] or "Email" in e["categories"],
    },
}

FIELD_CODE = re.compile(r"\s+%[fFuUdDnNickvm]")


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def fail(message: str) -> None:
    emit({"ok": False, "message": message})
    raise SystemExit(1)


# ---------------------------------------------------------------------------
# Desktop entries
# ---------------------------------------------------------------------------

def parse_desktop(path: Path) -> dict | None:
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    try:
        cp.read(path, encoding="utf-8")
    except (configparser.Error, UnicodeDecodeError, OSError):
        return None
    if not cp.has_section("Desktop Entry"):
        return None
    d = cp["Desktop Entry"]
    if d.get("Type", "Application") != "Application":
        return None
    if d.get("Hidden", "false").lower() == "true" or d.get("NoDisplay", "false").lower() == "true":
        return None
    exec_line = d.get("Exec", "")
    if not exec_line:
        return None
    try_exec = d.get("TryExec", "")
    if try_exec and not (shutil.which(try_exec) or Path(try_exec).exists()):
        return None
    categories = [c for c in d.get("Categories", "").split(";") if c]
    mimes = [m for m in d.get("MimeType", "").split(";") if m]
    return {
        "name": d.get("Name", path.stem),
        "icon": d.get("Icon", ""),
        "exec": FIELD_CODE.sub("", exec_line).strip(),
        "terminal": d.get("Terminal", "false").lower() == "true",
        "categories": categories,
        "mimes": mimes,
        "is_browser": "WebBrowser" in categories,
    }


def desktop_id(base: Path, path: Path) -> str:
    return str(path.relative_to(base)).replace("/", "-")


def load_apps() -> dict[str, dict]:
    apps: dict[str, dict] = {}
    for base in app_dirs():                     # earlier dirs win (user > flatpak > system)
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.desktop")):
            did = desktop_id(base, path)
            if did in apps:
                continue
            entry = parse_desktop(path)
            if entry is not None:
                entry["id"] = did
                apps[did] = entry
    return apps


# ---------------------------------------------------------------------------
# Current defaults
# ---------------------------------------------------------------------------

def read_mimeapps(path: Path) -> dict[str, list[str]]:
    defaults: dict[str, list[str]] = {}
    section = None
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return defaults
    for line in lines:
        line = line.strip()
        if line.startswith("["):
            section = line
        elif section == "[Default Applications]" and "=" in line:
            key, _, value = line.partition("=")
            defaults[key.strip()] = [v for v in value.strip().split(";") if v]
    return defaults


def mime_default(mime: str) -> str:
    for path in (MIMEAPPS, Path("/etc/xdg/mimeapps.list"), Path("/usr/share/applications/mimeapps.list")):
        found = read_mimeapps(path).get(mime)
        if found:
            return found[0]
    if shutil.which("xdg-mime"):
        try:
            out = subprocess.run(["xdg-mime", "query", "default", mime], capture_output=True,
                                 text=True, timeout=5).stdout.strip()
            if out:
                return out.splitlines()[0]
        except (OSError, subprocess.TimeoutExpired):
            pass
    return ""


def hypr_value(var: str) -> str:
    try:
        match = re.search(r'^\s*(?:local\s+)?' + var + r'\s*=\s*"([^"]*)"', HYPR_CONF.read_text(), re.M)
        return match.group(1) if match else ""
    except OSError:
        return ""


def first_program(command: str) -> str:
    for token in command.split():
        if token in ("uwsm", "app", "--", "env", "exec", "setsid", "flatpak", "run") or "=" in token \
                or token.startswith("-"):
            continue
        return Path(token).name
    return ""


def match_by_command(command: str, candidates: list[dict]) -> str:
    """Which candidate is the Hyprland command? (`nautilus --new-window` -> org.gnome.Nautilus)"""
    if not command:
        return ""
    for app in candidates:
        if app["exec"] == command:
            return app["id"]
    prog = first_program(command).lower()
    for app in candidates:
        if first_program(app["exec"]).lower() == prog:
            return app["id"]
    for app in candidates:                      # flatpak: last part of the app id
        if app["id"].lower().removesuffix(".desktop").split(".")[-1] == prog:
            return app["id"]
    return ""


# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------

def login_shell() -> str:
    try:
        return pwd.getpwuid(os.getuid()).pw_shell
    except KeyError:
        return os.environ.get("SHELL", "")


def available_shells() -> list[str]:
    out, seen = [], set()
    try:
        lines = Path("/etc/shells").read_text().splitlines()
    except OSError:
        lines = []
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or not Path(line).exists():
            continue
        name = Path(line).name
        if name in ("nologin", "false", "git-shell", "rbash", "rzsh", "tmux", "screen", "systemd-home-fallback-shell"):
            continue
        real = os.path.realpath(line)
        if real in seen:
            continue
        seen.add(real)
        out.append(line)
    # prefer /usr/bin/... spelling for display
    out.sort(key=lambda p: (Path(p).name, not p.startswith("/usr/bin")))
    dedup, names = [], set()
    for p in out:
        if Path(p).name not in names:
            names.add(Path(p).name)
            dedup.append(p)
    return dedup


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def scan() -> None:
    apps = load_apps()
    categories = []
    for key, cat in CATEGORIES.items():
        candidates = sorted((a for a in apps.values() if cat["match"](a)), key=lambda a: a["name"].lower())
        if key == "terminal":
            candidates = [a for a in candidates if not a["terminal"]]
        current = ""
        if cat["hypr"]:
            current = match_by_command(hypr_value(cat["hypr"]), candidates)
        if not current and cat["mimes"]:
            current = mime_default(cat["mimes"][0])
        if key == "terminal" and not current:
            current = match_by_command(os.environ.get("TERMINAL", ""), candidates)
        categories.append({
            "key": key,
            "label": cat["label"],
            "current": current,
            "currentName": apps[current]["name"] if current in apps else "",
            "options": [{"id": a["id"], "name": a["name"], "icon": a["icon"]} for a in candidates],
        })
    shells = available_shells()
    emit({
        "ok": True,
        "categories": categories,
        "shell": {"current": login_shell(), "options": shells},
    })


def write_mimeapps(mimes: list[str], app_id: str) -> None:
    lines: list[str] = []
    try:
        lines = MIMEAPPS.read_text().splitlines()
    except OSError:
        pass
    out, section, done, has_section = [], None, set(), False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("["):
            if section == "[Default Applications]":
                # new keys go before the blank line(s) that end the section
                tail = []
                while out and not out[-1].strip():
                    tail.append(out.pop())
                out.extend(f"{m}={app_id};" for m in mimes if m not in done)
                out.extend(tail)
                done.update(mimes)
            section = stripped
            has_section = has_section or section == "[Default Applications]"
            out.append(line)
            continue
        if section == "[Default Applications]" and "=" in stripped:
            key = stripped.partition("=")[0].strip()
            if key in mimes:
                if key not in done:
                    out.append(f"{key}={app_id};")
                    done.add(key)
                continue
        out.append(line)
    if section == "[Default Applications]":
        out.extend(f"{m}={app_id};" for m in mimes if m not in done)
        done.update(mimes)
    if not has_section:
        if out and out[-1].strip():
            out.append("")
        out.append("[Default Applications]")
        out.extend(f"{m}={app_id};" for m in mimes)
    MIMEAPPS.parent.mkdir(parents=True, exist_ok=True)
    MIMEAPPS.write_text("\n".join(out) + "\n")


def set_hypr(var: str, command: str) -> bool:
    try:
        text = HYPR_CONF.read_text()
    except OSError:
        return False
    escaped = command.replace("\\", "\\\\").replace('"', '\\"')
    pattern = re.compile(r'^(\s*(?:local\s+)?' + var + r'\s*=\s*)"[^"]*"', re.M)
    new, count = pattern.subn(lambda m: m.group(1) + '"' + escaped + '"', text, count=1)
    if count == 0:
        return False
    if new != text:
        HYPR_CONF.write_text(new)
        try:
            subprocess.run(["hyprctl", "reload"], capture_output=True, timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            pass
    return True


def set_xdg_terminal(app_id: str) -> None:
    try:
        lines = [l for l in XDG_TERMINALS.read_text().splitlines() if l.strip() and l.strip() != app_id]
    except OSError:
        lines = []
    XDG_TERMINALS.parent.mkdir(parents=True, exist_ok=True)
    XDG_TERMINALS.write_text("\n".join([app_id] + lines) + "\n")


def set_default(key: str, app_id: str) -> None:
    if key not in CATEGORIES:
        fail(f"Unknown category: {key}")
    apps = load_apps()
    app = apps.get(app_id)
    if app is None:
        fail(f"{app_id} is not installed.")
    cat = CATEGORIES[key]
    notes = []
    if cat["mimes"]:
        write_mimeapps(cat["mimes"], app_id)
    if cat["hypr"]:
        if set_hypr(cat["hypr"], app["exec"]):
            notes.append(f"SUPER + {'Q' if key == 'terminal' else 'E' if key == 'files' else 'B'} opens it")
    if key == "terminal":
        set_xdg_terminal(app_id)
        # the terminal colours / blur follow the new terminal
        termctl = CONFIG / "quickshell/scripts/yakushi-termctl.py"
        if termctl.exists():
            subprocess.Popen(["python3", str(termctl), "sync"], stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
    message = f"{app['name']} is now the default {cat['label'].lower()}"
    emit({"ok": True, "key": key, "current": app_id, "currentName": app["name"],
          "message": message + (" — " + ", ".join(notes) if notes else "") + "."})


def set_shell(path: str) -> None:
    if path not in available_shells():
        fail("That shell is not listed in /etc/shells.")
    if os.path.realpath(path) == os.path.realpath(login_shell()):
        emit({"ok": True, "shell": path, "message": "Already your login shell."})
        return
    user = pwd.getpwuid(os.getuid()).pw_name
    if not shutil.which("pkexec"):
        fail("pkexec is missing; run: chsh -s " + path)
    proc = subprocess.run(["pkexec", "usermod", "--shell", path, user], capture_output=True, text=True)
    if proc.returncode != 0:
        fail("Not changed (authentication cancelled or failed).")
    emit({"ok": True, "shell": path,
          "message": f"Login shell is now {Path(path).name}. New terminals use it after you log out and back in."})


def main() -> None:
    args = sys.argv[1:]
    if args == ["scan"]:
        scan()
    elif len(args) == 3 and args[0] == "set":
        set_default(args[1], args[2])
    elif len(args) == 2 and args[0] == "shell":
        set_shell(args[1])
    else:
        fail("Usage: scan | set <category> <desktop-id> | shell <path>")


if __name__ == "__main__":
    main()
