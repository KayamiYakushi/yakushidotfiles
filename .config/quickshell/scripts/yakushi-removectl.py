#!/usr/bin/env python3
"""Remove a package and what it left behind. Used by Settings -> Tasks.

    yakushi-removectl.py search <text>      installed packages matching the text
    yakushi-removectl.py plan <json>        what removing would do, changes nothing
    yakushi-removectl.py remove <json>      do it
    yakushi-removectl.py removed            what was removed before (the Yakushi trash)
    yakushi-removectl.py undo <id>          put it back: reinstall, restore files, re-enable
    yakushi-removectl.py empty <id>         delete those saved files for good

<json> is {"target": ["name", ...], "cascade": false, "files": ["~/.config/x", ...]}
("cascade": also remove the programs that need it; "files": which of the
found files in your home folder go - for `remove` only).

What `plan` looks at:
  * the packages that go: the target, and its dependencies nothing else
    needs (pacman -Rns), or with "cascade" the programs that need it too
  * programs that need it (then nothing goes until you allow "cascade")
  * protected packages: the base system, kernels, boot and keyrings, and
    what Yakushi itself runs on - these are never removed here
  * running processes of those packages (closed after the removal)
  * services they ship that are enabled or running (disabled and stopped)
  * files in your home folder with the program's name (~/.config,
    ~/.local/share, ~/.local/state, ~/.cache, ~/.<name>, autostart entries):
    they are moved to ~/.local/share/yakushi-trash, not deleted, so UNDO
    can bring everything back until you empty it
  * lines in your Hyprland config that start it (shown, not edited)

The removal itself is one pkexec call (one password prompt): stop and
disable the services, then pacman -Rns. pacman -n also deletes the system
config files instead of leaving .pacsave copies. If you cancel the password
prompt, nothing is changed.
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOME = Path.home()
TRASH = HOME / ".local/share/yakushi-trash"
NAME_RE = re.compile(r"^[A-Za-z0-9@._+-]+$")
UNIT_RE = re.compile(r"^[A-Za-z0-9@._:+\-]+\.(service|socket|timer|path)$")

sys.dont_write_bytecode = True            # no __pycache__ next to your config
_spec = importlib.util.spec_from_file_location("yakushi_taskctl", HERE / "yakushi-taskctl.py")
tasks = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tasks)

# never removed here: Linux, booting, package keys, and what Yakushi runs on
HARD = {
    "base", "filesystem", "glibc", "gcc-libs", "bash", "coreutils", "util-linux", "systemd", "systemd-libs",
    "systemd-sysvcompat", "pacman", "pacman-mirrorlist", "archlinux-keyring", "sudo", "shadow", "pam",
    "dbus", "dbus-broker", "dbus-broker-units", "polkit", "mkinitcpio", "dracut", "linux-firmware",
    "grub", "efibootmgr", "limine", "refind", "os-prober", "amd-ucode", "intel-ucode",
    "mesa", "vulkan-radeon", "vulkan-intel", "nvidia", "nvidia-open", "nvidia-utils",
    "hyprland", "quickshell", "python", "fish", "sddm", "networkmanager", "pipewire", "wireplumber",
    "xdg-desktop-portal-hyprland", "hyprpolkitagent", "ttf-jetbrains-mono-nerd", "noto-fonts-cjk", "qt6ct",
}
HARD_PATTERNS = [re.compile(p) for p in (
    r"^linux(-[a-z0-9]+)*$",              # kernels (linux, linux-lts, linux-cachyos, ...)
    r".*-keyring$", r".*-mirrorlist$", r"^cachyos-(settings|hooks|kernel-manager)$",
)]
KERNEL_EXTRA = re.compile(r"^linux.*-(headers|docs)$")      # these may go

# Yakushi uses these for one feature each: allowed, with a warning
SOFT = {
    "waybar": "the Waybar style of the top bar", "rofi": "the app launcher, clipboard and power menu",
    "kitty": "the default terminal (SUPER + Q)", "nautilus": "the default file manager (SUPER + E)",
    "firefox": "the default browser (SUPER + B)", "wl-clipboard": "copy and paste in scripts",
    "cliphist": "clipboard history (SUPER + V)", "grim": "screenshots", "slurp": "area screenshots",
    "brightnessctl": "screen brightness keys", "hyprsunset": "night light", "hyprlock": "the lock screen",
    "playerctl": "now playing in the top bar", "pavucontrol": "advanced sound settings", "cava": "the visualizer",
    "awww": "wallpapers", "jq": "a few scripts", "imagemagick": "picture previews", "bluez": "Bluetooth",
    "bluez-utils": "Bluetooth", "pipewire-pulse": "sound for most apps", "noto-fonts": "the interface font",
    "xdg-desktop-portal-gtk": "file pickers and light/dark apps", "dconf": "light/dark apps",
    "gsettings-desktop-schemas": "light/dark apps", "pciutils": "the GPU name in System", "xdg-utils": "opening links",
    "qt6-imageformats": "picture formats", "hyprtoolkit": "Hyprland dialogs",
}

# where some well-known apps keep their data (paths under your home folder)
KNOWN_DATA = {
    "firefox": [".mozilla/firefox", ".cache/mozilla/firefox"],
    "thunderbird": [".thunderbird", ".cache/thunderbird"],
    "chromium": [".config/chromium", ".cache/chromium"],
    "google-chrome": [".config/google-chrome", ".cache/google-chrome"],
    "brave-bin": [".config/BraveSoftware", ".cache/BraveSoftware"],
    "code": [".vscode-oss", ".config/Code - OSS"],
    "visual-studio-code-bin": [".vscode", ".config/Code"],
    "steam": [".steam", ".local/share/Steam"],
    "obs-studio": [".config/obs-studio"],
    "gimp": [".config/GIMP", ".cache/gimp"],
    "libreoffice-fresh": [".config/libreoffice"], "libreoffice-still": [".config/libreoffice"],
    "telegram-desktop": [".local/share/TelegramDesktop"],
    "spotify-launcher": [".local/share/spotify-launcher", ".config/spotify", ".cache/spotify"],
}
# big folders that hold your own things: found, but not ticked by default
PERSONAL = {".local/share/Steam": "your installed Steam games are in here", ".steam": "Steam's links to your games",
            ".mozilla/firefox": "bookmarks, passwords and history", ".thunderbird": "your mail",
            ".local/share/TelegramDesktop": "your Telegram session"}
# folders Yakushi itself manages or writes to
YAKUSHI_DIRS = {"hypr", "quickshell", "waybar", "rofi", "hyprpolkitagent", "qt6ct", "fish", "kitty", "yakushi",
                "yakushi-trash", "gtk-3.0", "gtk-4.0", "systemd", "autostart", "applications", "icons", "fonts"}
GENERIC = {"python", "lib", "share", "config", "data", "cache", "bin", "gtk", "qt", "x11", "fonts", "icons", "themes",
           "sounds", "applications", "systemd", "dbus", "pulse", "pipewire", "mime", "user", "default", "common",
           "local", "state", "tmp", "log", "logs", "run", "env", "utils", "tools", "core", "base", "desktop"}


def emit(obj: dict) -> None:
    print(json.dumps(obj))


def run(cmd: list[str], timeout: int = 60) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return subprocess.CompletedProcess(cmd, 127, "", f"{cmd[0]} is not installed")
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, "", f"{cmd[0]} took too long")


# ---- protection ----------------------------------------------------------------------
def running_kernel_pkg() -> str:
    res = run(["pacman", "-Qqo", f"/usr/lib/modules/{os.uname().release}/vmlinuz"], 10)
    return res.stdout.strip() if res.returncode == 0 else ""


def protected(name: str, kernel: str) -> str:
    """'' or why this package is never removed here"""
    if name == kernel:
        return "the kernel you are running"
    if KERNEL_EXTRA.match(name):
        return ""
    if name in HARD or any(p.match(name) for p in HARD_PATTERNS):
        if name in ("hyprland", "quickshell", "python", "fish", "sddm", "xdg-desktop-portal-hyprland",
                    "hyprpolkitagent", "ttf-jetbrains-mono-nerd", "noto-fonts-cjk", "qt6ct"):
            return "Yakushi runs on it"
        if name.startswith("linux"):
            return "a kernel: your computer boots with it"
        return "the base system needs it"
    return ""


# ---- what goes ------------------------------------------------------------------------
def pacman_plan(targets: list[str], cascade: bool) -> tuple[list[str], dict[str, list[str]], str]:
    """(packages that go, {package: [needed by]} when blocked, error)"""
    flags = "-Rnscp" if cascade else "-Rnsp"
    res = run(["pacman", flags, "--print-format", "%n", *targets])
    if res.returncode == 0:
        return [l.strip() for l in res.stdout.splitlines() if l.strip() and not l.startswith(("::", "warning"))], {}, ""
    blocked: dict[str, list[str]] = {}
    for line in (res.stderr + res.stdout).splitlines():
        m = re.search(r"removing (\S+) breaks dependency '([^']+)' required by (\S+)", line)
        if m:
            blocked.setdefault(m.group(1), []).append(m.group(3))
    if blocked:
        return [], blocked, ""
    err = [l for l in res.stderr.splitlines() if l.strip()]
    return [], {}, (err[-1].removeprefix("error: ") if err else "pacman could not plan this.")


def package_files(names: list[str]) -> list[str]:
    res = run(["pacman", "-Qlq", *names], 60)
    return [l.strip() for l in res.stdout.splitlines() if l.strip()]


def unit_state(unit: str, user: bool) -> tuple[bool, bool]:
    base = ["systemctl"] + (["--user"] if user else [])
    enabled = run(base + ["is-enabled", unit], 10).stdout.strip() in ("enabled", "enabled-runtime", "linked")
    active = run(base + ["is-active", unit], 10).stdout.strip() in ("active", "activating", "reloading")
    return enabled, active


def units_of(files: list[str]) -> dict[str, list[str]]:
    out = {"system": [], "user": []}
    for f in files:
        m = re.match(r"^/usr/lib/systemd/(system|user)/([^/]+\.(service|socket|timer|path))$", f)
        if not m or "@." in m.group(2):                 # templates are never enabled as such
            continue
        user = m.group(1) == "user"
        enabled, active = unit_state(m.group(2), user)
        if enabled or active:
            out["user" if user else "system"].append(m.group(2))
    return out


def processes_of(files: list[str]) -> list[dict]:
    wanted = {f for f in files if f.startswith(("/usr/bin/", "/usr/lib/", "/opt/", "/usr/share/"))}
    out = []
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        try:
            exe = os.readlink(f"/proc/{pid}/exe").removesuffix(" (deleted)")
        except OSError:
            continue
        argv = tasks.cmdline(pid)
        script = tasks.script_of(argv)
        if exe in wanted or (script and script in wanted):
            st = tasks.stat(pid)
            if st:
                uid = tasks.uid_of(pid)
                out.append({"pid": pid, "start": st["start"], "name": tasks.display_name(st["comm"], argv),
                            "user": tasks.user_name(uid), "mine": uid == os.getuid()})
    return out


def candidate_names(targets: list[str], files: list[str]) -> set[str]:
    names = set()
    for t in targets:
        names.add(t.lower())
        for suffix in ("-bin", "-git", "-desktop", "-launcher", "-studio", "-fresh", "-still"):
            if t.lower().endswith(suffix):
                names.add(t.lower()[: -len(suffix)])
    for f in files:
        if f.startswith("/usr/bin/") and not f.endswith("/"):
            names.add(os.path.basename(f).lower())
        m = re.match(r"^/usr/share/applications/(.+)\.desktop$", f)
        if m:
            app_id = m.group(1)
            names.add(app_id.lower())
            names.add(app_id.split(".")[-1].lower())
            text = tasks.read(f)
            wm = re.search(r"^StartupWMClass=(.+)$", text, re.M)
            if wm:
                names.add(wm.group(1).strip().lower())
    return {n for n in names if len(n) >= 3 and n not in GENERIC}


def folder_size(path: Path, budget: float = 1.5) -> tuple[int, bool]:
    """bytes, and whether counting stopped early (huge folders)"""
    if path.is_symlink() or path.is_file():
        try:
            return path.lstat().st_size, False
        except OSError:
            return 0, False
    total, deadline = 0, time.monotonic() + budget
    for root, dirs, files in os.walk(path, onerror=lambda e: None):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
            except OSError:
                pass
        if time.monotonic() > deadline:
            return total, True
    return total, False


def leftovers(targets: list[str], files: list[str]) -> list[dict]:
    names = candidate_names(targets, files)
    found: dict[str, dict] = {}

    def add(path: Path, note: str = "", checked: bool = True) -> None:
        rel = str(path.relative_to(HOME))
        if rel in found or not (path.exists() or path.is_symlink()):
            return
        top = rel.split("/")
        if len(top) > 1 and top[0] in (".config", ".local") and top[-1].lower() in YAKUSHI_DIRS:
            return
        size, partial = folder_size(path)
        if rel in PERSONAL:
            note, checked = PERSONAL[rel], False
        found[rel] = {"path": "~/" + rel, "size": size, "partial": partial, "checked": checked, "note": note}

    for t in targets:
        for rel in KNOWN_DATA.get(t, []):
            add(HOME / rel)

    def matches(entry: str) -> bool:
        e = entry.lower().lstrip(".")
        for ext in (".conf", ".json", ".toml", ".ini", ".yml", ".yaml", ".desktop", ".lock", ".log", "rc"):
            if e.endswith(ext) and e[: -len(ext)] in names:
                return True
        return e in names

    for base in (HOME / ".config", HOME / ".local/share", HOME / ".local/state", HOME / ".cache"):
        try:
            entries = list(os.scandir(base))
        except OSError:
            continue
        for entry in entries:
            if entry.name.lower() in YAKUSHI_DIRS:
                continue
            if matches(entry.name):
                add(Path(entry.path))
    try:
        for entry in os.scandir(HOME):
            if entry.name.startswith(".") and entry.name not in (".config", ".local", ".cache") and matches(entry.name):
                add(Path(entry.path))
    except OSError:
        pass
    for folder in (HOME / ".config/autostart", HOME / ".local/share/applications", HOME / ".config/systemd/user"):
        try:
            entries = list(os.scandir(folder))
        except OSError:
            continue
        for entry in entries:
            stem = entry.name.rsplit(".", 1)[0].lower()
            if stem in names or stem.split(".")[-1] in names:
                add(Path(entry.path), "starts it or shows it in the app list")
    return sorted(found.values(), key=lambda f: f["path"])


def mentions(files: list[str]) -> list[str]:
    bins = sorted({os.path.basename(f) for f in files if f.startswith("/usr/bin/") and len(os.path.basename(f)) > 2})
    if not bins:
        return []
    out = []
    pats = [re.compile(r'(^|[\s/"\'(])' + re.escape(b) + r'($|[\s"\')])') for b in bins]
    for rel in (".config/hypr/hyprland.lua", ".config/hypr/keybinds.lua"):
        lines = tasks.read(HOME / rel).splitlines()
        for i, line in enumerate(lines):
            code = line.split("--", 1)[0]
            if any(p.search(code) for p in pats):
                label = ""
                if rel.endswith("keybinds.lua") and i and "YAKUSHI_BIND" in lines[i - 1] and lines[i - 1].count("|") >= 2:
                    label = lines[i - 1].split("|")[2].strip()
                keys = re.match(r'\s*yakushi_bind\("[^"]+",\s*"([^"]+)"', line)
                if keys:
                    out.append(f"The shortcut {keys.group(1)}" + (f" ({label})" if label else "")
                               + " runs it: it will do nothing afterwards.")
                else:
                    out.append(f"~/{rel} line {i + 1} starts it: that line will fail quietly.")
    return out


def plan(request: dict) -> dict:
    targets = [t for t in request.get("target", []) if isinstance(t, str) and NAME_RE.match(t)]
    if not targets:
        return {"ok": False, "message": "No package given."}
    pkgs = tasks.load_packages()
    missing = [t for t in targets if pkgs and t not in pkgs]
    if missing:
        return {"ok": False, "message": "Not installed: " + ", ".join(missing)}
    cascade = request.get("cascade") is True
    names, blocked, err = pacman_plan(targets, cascade)
    if err:
        return {"ok": False, "message": err}
    kernel = running_kernel_pkg()
    if blocked:
        needed = {k: sorted(set(v)) for k, v in blocked.items()}
        guarded = [{"name": n, "reason": protected(n, kernel)} for by in needed.values() for n in by if protected(n, kernel)]
        return {"ok": True, "target": targets, "cascade": cascade, "blocked": needed, "protected": guarded,
                "remove": [], "running": [], "units": {"system": [], "user": []}, "files": [], "mentions": [],
                "soft": [], "freed": 0, "canRemove": False}
    guarded = [{"name": n, "reason": protected(n, kernel)} for n in names if protected(n, kernel)]
    files = package_files(names) if names else []
    remove = []
    for n in names:
        info = pkgs.get(n, {})
        remove.append({"name": n, "version": info.get("version", ""), "size": info.get("size", 0),
                       "explicit": info.get("explicit", False), "desc": info.get("desc", ""),
                       "why": "you chose it" if n in targets else ("installed by you" if info.get("explicit") else "a dependency nothing else needs")})
    soft = [{"name": n, "reason": SOFT[n]} for n in names if n in SOFT]
    # UNDO reinstalls from the official repositories: say which it cannot
    norepo = [n for n in names if run(["pacman", "-Si", "--", n], 20).returncode != 0]
    found = leftovers(targets, files)
    freed = sum(r["size"] for r in remove)
    return {
        "ok": True, "target": targets, "cascade": cascade, "blocked": {}, "protected": guarded,
        "remove": remove, "running": processes_of(files), "units": units_of(files),
        "files": found, "mentions": mentions(files), "soft": soft, "freed": freed,
        "canRemove": bool(names) and not guarded, "notInRepos": norepo,
    }


# ---- doing it ------------------------------------------------------------------------
def end_processes(procs: list[dict]) -> None:
    mine = [p for p in procs if p["mine"]]
    for p in mine:
        tasks.send(p["pid"], p["start"], signal.SIGTERM)
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline and any(tasks.alive(p["pid"], p["start"]) for p in mine):
        time.sleep(0.1)
    for p in mine:
        if tasks.alive(p["pid"], p["start"]):
            tasks.send(p["pid"], p["start"], signal.SIGKILL)


def stamp_dir(target: str) -> Path:
    TRASH.mkdir(parents=True, exist_ok=True)
    base = time.strftime("%Y-%m-%d_%H-%M-%S") + "_" + target
    d, n = TRASH / base, 1
    while d.exists():
        n += 1
        d = TRASH / f"{base}-{n}"
    return d


def move_out(path: Path, store: Path) -> None:
    store.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), str(store))


def remove(request: dict) -> dict:
    p = plan(request)
    if not p.get("ok"):
        return p
    if p["blocked"]:
        return {"ok": False, "message": "Other programs need it. Allow removing them too, or keep it."}
    if p["protected"]:
        return {"ok": False, "message": "Protected: " + ", ".join(f"{g['name']} ({g['reason']})" for g in p["protected"])}
    if not p["remove"]:
        return {"ok": False, "message": "Nothing to remove."}
    names = [r["name"] for r in p["remove"]]
    chosen = {f.removeprefix("~/") for f in request.get("files", []) if isinstance(f, str)}
    files = [f for f in p["files"] if f["path"].removeprefix("~/") in chosen]       # only what plan found
    sys_units = [u for u in p["units"]["system"] if UNIT_RE.match(u)]
    user_units = [u for u in p["units"]["user"] if UNIT_RE.match(u)]
    if not all(NAME_RE.match(n) for n in names):
        return {"ok": False, "message": "Unexpected package name."}

    # 1. one password prompt: services off, then pacman (nothing changes if cancelled)
    script = ('while [ $# -gt 0 ] && [ "$1" != "--" ]; do systemctl disable --now "$1" >/dev/null 2>&1; shift; done; shift; '
              'exec pacman ' + ("-Rnsc" if p["cascade"] else "-Rns") + ' --noconfirm "$@"')
    res = run(["pkexec", "/bin/sh", "-c", script, "yakushi-remove", *sys_units, "--", *names], 900)
    if res.returncode in (126, 127):
        return {"ok": False, "message": "Cancelled: the password was not given. Nothing was changed."}
    still = [n for n in names if run(["pacman", "-Qq", n], 10).returncode == 0]
    if res.returncode != 0 and len(still) == len(names):
        err = [l for l in (res.stderr or res.stdout).splitlines() if l.strip()]
        return {"ok": False, "message": "pacman did not remove it: " + (err[-1] if err else "unknown error")}
    gone = [n for n in names if n not in still]
    pkgs_info = {r["name"]: r for r in p["remove"]}

    # 2. what kept running, your services
    end_processes(p["running"])
    for u in user_units:
        run(["systemctl", "--user", "disable", "--now", u], 30)

    # 3. your files -> the Yakushi trash, with a note on how to put it all back
    box = stamp_dir(p["target"][0])
    moved = []
    for f in files:
        src = HOME / f["path"].removeprefix("~/")
        if not (src.exists() or src.is_symlink()):
            continue
        store = box / "files" / f["path"].removeprefix("~/")
        try:
            move_out(src, store)
            moved.append({"path": f["path"], "size": f["size"]})
        except OSError:
            pass
    box.mkdir(parents=True, exist_ok=True)
    manifest = {
        "id": box.name, "time": int(time.time()), "target": p["target"], "cascade": p["cascade"],
        "packages": [{"name": n, "explicit": pkgs_info[n]["explicit"], "version": pkgs_info[n]["version"]} for n in gone],
        "unitsSystem": sys_units, "unitsUser": user_units, "files": moved,
        "freed": sum(pkgs_info[n]["size"] for n in gone) + sum(m["size"] for m in moved),
    }
    (box / "manifest.json").write_text(json.dumps(manifest, indent=2))
    msg = f"Removed {', '.join(gone)}."
    if moved:
        msg += f" {len(moved)} of your files are in the Yakushi trash: UNDO puts everything back."
    if still:
        msg += f" Still installed: {', '.join(still)}."
    return {"ok": True, "message": msg, "id": box.name, "removed": gone, "moved": moved}


# ---- the trash -----------------------------------------------------------------------
def manifests() -> list[dict]:
    out = []
    try:
        boxes = sorted(TRASH.iterdir(), reverse=True)
    except OSError:
        return out
    for box in boxes:
        try:
            m = json.loads((box / "manifest.json").read_text())
        except (OSError, ValueError):
            continue
        m["id"] = box.name
        out.append(m)
    return out


def find_box(box_id: str) -> Path | None:
    if not re.fullmatch(r"[\w.@+-]+", box_id):
        return None
    box = TRASH / box_id
    return box if (box / "manifest.json").exists() else None


def undo(box_id: str) -> dict:
    box = find_box(box_id)
    if box is None:
        return {"ok": False, "message": "Not in the Yakushi trash any more."}
    m = json.loads((box / "manifest.json").read_text())
    pkgs = [p["name"] for p in m.get("packages", []) if NAME_RE.match(p["name"])]
    deps = [p["name"] for p in m.get("packages", []) if not p.get("explicit") and NAME_RE.match(p["name"])]
    units = [u for u in m.get("unitsSystem", []) if UNIT_RE.match(u)]
    problems = []
    if pkgs:
        script = ('p=""; while [ $# -gt 0 ] && [ "$1" != "--" ]; do p="$p $1"; shift; done; shift; '
                  'pacman -S --needed --noconfirm $p || exit 3; '
                  'd=""; while [ $# -gt 0 ] && [ "$1" != "--" ]; do d="$d $1"; shift; done; shift; '
                  '[ -n "$d" ] && pacman -D --asdeps $d >/dev/null; '
                  'for u in "$@"; do systemctl enable --now "$u" >/dev/null 2>&1; done; exit 0')
        res = run(["pkexec", "/bin/sh", "-c", script, "yakushi-undo", *pkgs, "--", *deps, "--", *units], 1800)
        if res.returncode in (126, 127):
            return {"ok": False, "message": "Cancelled: the password was not given. Nothing was changed."}
        if res.returncode != 0:
            err = [l for l in (res.stderr or res.stdout).splitlines() if l.strip()]
            problems.append("reinstalling failed (" + (err[-1] if err else "no internet, or not in the repositories") + ")")
    restored = 0
    for f in m.get("files", []):
        rel = f["path"].removeprefix("~/")
        src, dst = box / "files" / rel, HOME / rel
        if not (src.exists() or src.is_symlink()):
            continue
        if dst.exists() or dst.is_symlink():
            dst = dst.with_name(dst.name + ".restored")
        try:
            move_out(src, dst)
            restored += 1
        except OSError:
            problems.append(f"could not restore {f['path']}")
    for u in m.get("unitsUser", []):
        if UNIT_RE.match(u):
            run(["systemctl", "--user", "enable", "--now", u], 30)
    if problems and not restored and pkgs:
        return {"ok": False, "message": "Could not put it back: " + "; ".join(problems)}
    shutil.rmtree(box, ignore_errors=True)
    msg = "Put back: " + (", ".join(pkgs) if pkgs else "your files") + (f" and {restored} files." if restored and pkgs else ".")
    if problems:
        msg += " But: " + "; ".join(problems) + "."
    return {"ok": True, "message": msg}


def empty(box_id: str) -> dict:
    box = find_box(box_id)
    if box is None:
        return {"ok": False, "message": "Not in the Yakushi trash any more."}
    shutil.rmtree(box, ignore_errors=True)
    return {"ok": True, "message": "Deleted for good."}


def search(text: str) -> dict:
    q = text.strip().lower()
    pkgs = tasks.load_packages()
    kernel = running_kernel_pkg()
    hits = []
    for p in pkgs.values():
        if q and q not in p["name"].lower() and q not in p["desc"].lower():
            continue
        hits.append({"name": p["name"], "desc": p["desc"], "size": p["size"], "explicit": p["explicit"],
                     "protected": protected(p["name"], kernel)})
    hits.sort(key=lambda h: (not h["name"].lower().startswith(q), not h["explicit"], h["name"]))
    return {"ok": True, "packages": hits[:60], "total": len(hits)}


def main() -> None:
    a = sys.argv[1:]
    try:
        if len(a) == 2 and a[0] == "search":
            emit(search(a[1]))
        elif len(a) == 2 and a[0] in ("plan", "remove"):
            try:
                request = json.loads(a[1])
            except ValueError:
                request = None
            if not isinstance(request, dict):
                emit({"ok": False, "message": "Bad request."})
                return
            emit(plan(request) if a[0] == "plan" else remove(request))
        elif a == ["removed"]:
            emit({"ok": True, "removed": manifests()})
        elif len(a) == 2 and a[0] == "undo":
            emit(undo(a[1]))
        elif len(a) == 2 and a[0] == "empty":
            emit(empty(a[1]))
        else:
            emit({"ok": False, "message": "usage: search <text> | plan <json> | remove <json> | removed | undo <id> | empty <id>"})
    except Exception as e:                       # always answer the page
        emit({"ok": False, "message": f"Unexpected error: {e}"})


if __name__ == "__main__":
    main()
