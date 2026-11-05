#!/usr/bin/env python3
"""Mouse cursor themes for Settings -> Input -> Cursor.

    yakushi-cursorctl.py list        installed themes + what is in use (JSON)
    yakushi-cursorctl.py set <id>    use theme <id> (its folder name)
    yakushi-cursorctl.py size <px>   cursor size (8 .. 128)
    yakushi-cursorctl.py shake on|off
                                     grow the cursor while you shake the mouse
                                     (yakushi-shake.py, KDE style)
    yakushi-cursorctl.py hold <s>    how long it stays big after the shaking
                                     stops (0.1 .. 3 seconds)
    yakushi-cursorctl.py login       give Hyprland's own pointer the saved
                                     theme (hyprland.lua runs it at login)

A theme is any folder in an icon directory with a `cursors/` folder
(XCursor) or a `manifest.hl` (hyprcursor). `list` also saves a small PNG of
each theme's arrow in ~/.cache/yakushi/cursors for the previews.

`set` changes it now (hyprctl setcursor) and for the next login:
  * ~/.config/hypr/cursor.local.lua   XCURSOR_THEME / HYPRCURSOR_THEME
  * GSettings cursor-theme + gtk-3.0 / gtk-4.0 settings.ini (GTK apps)
  * ~/.icons/default/index.theme      (XWayland and other X11 apps)
Shake to find is yakushi-shake.py, started here and at login while it is
on; with it off nothing extra runs. It grows the real cursor through a tiny
helper theme, Yakushi-Shake (your arrow, hand and text cursor, pre-scaled
to a few sizes), which Hyprland loads in a blink, unlike a full theme.
Runs only when called.
"""
from __future__ import annotations

import configparser
import io
import json
import os
import re
import shutil
import signal
import struct
import subprocess
import sys
import zipfile
import zlib
from pathlib import Path


def write_safely(path, text: str) -> None:
    """Write a config file in place (same file, so watchers and symlinks keep
    working), but only after a trial copy proved the disk has room for it: on
    a full disk the old file stays whole instead of ending up empty."""
    real = os.path.realpath(path)
    data = text.encode()
    trial = os.path.join(os.path.dirname(real), "." + os.path.basename(real) + ".yakushi-new")
    try:
        with open(trial, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
    finally:
        try:
            os.unlink(trial)
        except OSError:
            pass
    try:
        with open(real, "rb") as f:
            old = f.read()
    except FileNotFoundError:
        old = None
    try:
        with open(real, "r+b" if old is not None else "wb") as f:
            f.write(data)
            f.truncate()
    except OSError:
        if old is not None:                      # put the old one back
            with open(real, "r+b") as f:
                f.write(old)
                f.truncate()
        raise


HOME = Path.home()
HYPR = HOME / ".config/hypr"
LOCAL = HYPR / "cursor.local.lua"
CACHE = HOME / ".cache/yakushi/cursors"
OWN = "Yakushi-Red"                      # shipped with Yakushi
SHAKER = Path(__file__).resolve().parent / "yakushi-shake.py"
SHAKE_PID = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "yakushi" / "shake.pid"
ARROWS = ("left_ptr", "default", "arrow", "top_left_arrow")
SHAKE_THEME = "Yakushi-Shake"                 # generated, never listed
SHAKE_STEPS = (1.0, 1.25, 1.5, 1.8, 2.1, 2.4)
SHAKE_SHAPES = {                              # file -> names to look for / aliases
    "default": (ARROWS, ("left_ptr", "arrow", "top_left_arrow")),
    "pointer": (("pointer", "hand2", "hand1", "pointing_hand"), ("hand1", "hand2", "pointing_hand")),
    "text": (("text", "xterm", "ibeam"), ("xterm", "ibeam")),
}


def icon_dirs() -> list[Path]:
    dirs = [HOME / ".local/share/icons", HOME / ".icons"]
    data = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    dirs += [Path(p) / "icons" for p in data.split(":") if p]
    seen, out = set(), []
    for d in dirs:
        if d not in seen:
            seen.add(d)
            out.append(d)
    return out


def theme_name(folder: Path) -> str:
    for f in ("index.theme", "manifest.hl"):
        try:
            text = (folder / f).read_text(errors="ignore")
        except OSError:
            continue
        m = re.search(r"^\s*name\s*=\s*(.+?)\s*$", text, re.M | re.I)
        if m:
            return m.group(1)
    return folder.name


def find_themes() -> list[dict]:
    themes: dict[str, dict] = {}
    for base in icon_dirs():
        try:
            entries = sorted(base.iterdir())
        except OSError:
            continue
        for folder in entries:
            if folder.name in themes or folder.name in ("default", SHAKE_THEME) or not folder.is_dir():
                continue
            xcur = (folder / "cursors").is_dir()
            hcur = (folder / "manifest.hl").is_file()
            if not (xcur or hcur):
                continue
            themes[folder.name] = {
                "id": folder.name,
                "name": theme_name(folder),
                "path": str(folder),
                "kind": "hyprcursor" if hcur else "xcursor",
                "yakushi": folder.name.startswith(OWN),        # Yakushi Red and Yakushi Red Dark
                "user": str(folder).startswith(str(HOME)),
            }
    # ours first, then by name
    return sorted(themes.values(), key=lambda t: (not t["yakushi"], t["name"].lower()))


# ---- previews ---------------------------------------------------------------
def png_bytes(w: int, h: int, rgba: bytes) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    rows = b"".join(b"\x00" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def xcursor_image(path: Path, pick) -> dict | None:
    """One frame of an XCursor file: `pick(sizes)` chooses the nominal size.
    Returns nominal size, width, height, hotspot and a PNG."""
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if data[:4] != b"Xcur":
        return None
    _, _, ntoc = struct.unpack_from("<III", data, 4)
    first = {}                                   # nominal size -> first frame
    for i in range(ntoc):
        typ, nominal, pos = struct.unpack_from("<III", data, 16 + i * 12)
        if typ == 0xFFFD0002 and nominal not in first:
            first[nominal] = pos
    if not first:
        return None
    nominal = pick(sorted(first))
    _, _, _, _, w, h, xhot, yhot, _ = struct.unpack_from("<IIIIIIIII", data, first[nominal])
    px = data[first[nominal] + 36: first[nominal] + 36 + w * h * 4]
    out = bytearray(w * h * 4)
    for i in range(w * h):
        b, g, r, a = px[i * 4: i * 4 + 4]
        if a:                                    # premultiplied ARGB -> RGBA
            r, g, b = (min(255, c * 255 // a) for c in (r, g, b))
        out[i * 4: i * 4 + 4] = bytes((r, g, b, a))
    return {"nominal": nominal, "w": w, "h": h, "hotX": xhot, "hotY": yhot,
            "png": png_bytes(w, h, bytes(out))}


def closest(want: int):
    """smallest size >= want, else the largest there is"""
    return lambda sizes: next((s for s in sizes if s >= want), sizes[-1])


def xcursor_png(path: Path, want: int = 48) -> bytes | None:
    img = xcursor_image(path, closest(want))
    return img["png"] if img else None


def hyprcursor_png(folder: Path) -> bytes | None:
    d = folder / "hyprcursors"
    for shape in ARROWS:
        f = d / f"{shape}.hlc"
        if not f.is_file():
            continue
        try:
            with zipfile.ZipFile(f) as z:
                pngs = sorted((n for n in z.namelist() if n.lower().endswith(".png")),
                              key=lambda n: -z.getinfo(n).file_size)
                if pngs:
                    return z.read(pngs[0])
        except (OSError, zipfile.BadZipFile):
            pass
    return None


def arrow_file(folder: Path) -> Path | None:
    return next((folder / "cursors" / n for n in ARROWS if (folder / "cursors" / n).exists()), None)


def preview(theme: dict) -> str:
    folder = Path(theme["path"])
    CACHE.mkdir(parents=True, exist_ok=True)
    out = CACHE / f"{theme['id']}.png"
    src = arrow_file(folder)
    stamp = (src or folder).stat().st_mtime if (src or folder).exists() else 0
    if out.exists() and out.stat().st_mtime >= stamp:
        return str(out)
    blob = xcursor_png(src.resolve()) if src else None
    if blob is None and theme["kind"] == "hyprcursor":
        blob = hyprcursor_png(folder)
    if blob is None:
        return ""
    out.write_bytes(blob)
    return str(out)


# ---- the shake helper theme ---------------------------------------------------
def xcursor_frames(path: Path) -> dict:
    """nominal size -> (w, h, xhot, yhot, premultiplied BGRA pixels), first frames"""
    try:
        data = path.read_bytes()
    except OSError:
        return {}
    if data[:4] != b"Xcur":
        return {}
    _, _, ntoc = struct.unpack_from("<III", data, 4)
    out = {}
    for i in range(ntoc):
        typ, nominal, pos = struct.unpack_from("<III", data, 16 + i * 12)
        if typ == 0xFFFD0002 and nominal not in out:
            _, _, _, _, w, h, xh, yh, _ = struct.unpack_from("<IIIIIIIII", data, pos)
            out[nominal] = (w, h, xh, yh, data[pos + 36: pos + 36 + w * h * 4])
    return out


def resample(w: int, h: int, px: bytes, nw: int, nh: int) -> bytes:
    """bilinear on premultiplied pixels (correct edges, no dark halos)"""
    out = bytearray(nw * nh * 4)
    sx, sy = w / nw, h / nh
    for y in range(nh):
        fy = max(0.0, (y + 0.5) * sy - 0.5)
        y0 = min(int(fy), h - 1)
        y1 = min(y0 + 1, h - 1)
        ty = fy - y0
        for x in range(nw):
            fx = max(0.0, (x + 0.5) * sx - 0.5)
            x0 = min(int(fx), w - 1)
            x1 = min(x0 + 1, w - 1)
            tx = fx - x0
            i00, i01 = (y0 * w + x0) * 4, (y0 * w + x1) * 4
            i10, i11 = (y1 * w + x0) * 4, (y1 * w + x1) * 4
            o = (y * nw + x) * 4
            for c in range(4):
                top = px[i00 + c] * (1 - tx) + px[i01 + c] * tx
                bot = px[i10 + c] * (1 - tx) + px[i11 + c] * tx
                out[o + c] = int(top * (1 - ty) + bot * ty + 0.5)
    return bytes(out)


def xcursor_bytes(images: list) -> bytes:
    """images: (nominal, w, h, xhot, yhot, pixels) -> an XCursor file"""
    head = struct.pack("<4sIII", b"Xcur", 16, 0x10000, len(images))
    pos = 16 + 12 * len(images)
    toc, body = b"", b""
    for nominal, w, h, xh, yh, px in images:
        toc += struct.pack("<III", 0xFFFD0002, nominal, pos + len(body))
        body += struct.pack("<IIIIIIIII", 36, 0xFFFD0002, nominal, 1, w, h, xh, yh, 0) + px
    return head + toc + body


def theme_chain(tid: str) -> list[Path]:
    """the theme, what it inherits (a few levels), then ours and Adwaita"""
    themes = {t["id"]: Path(t["path"]) for t in find_themes()}
    chain, todo = [], [tid]
    while todo and len(chain) < 6:
        name = todo.pop(0)
        if name in themes and themes[name] not in chain:
            chain.append(themes[name])
            m = re.search(r"^\s*Inherits\s*=\s*(.+)$", read(themes[name] / "index.theme"), re.M)
            if m:
                todo += [n.strip() for n in m.group(1).split(",") if n.strip()]
    for extra in (OWN, "Adwaita"):
        if extra in themes and themes[extra] not in chain:
            chain.append(themes[extra])
    return chain


def write_shake_theme() -> dict:
    """~/.local/share/icons/Yakushi-Shake: arrow, hand and text cursor of the
    theme in use at every size the shake grows through"""
    tid, base = current(), size()
    sizes = sorted({max(8, round(base * f)) for f in SHAKE_STEPS})
    chain = theme_chain(tid)
    folder = HOME / ".local/share/icons" / SHAKE_THEME
    if folder.exists():
        shutil.rmtree(folder)
    (folder / "cursors").mkdir(parents=True)
    (folder / "index.theme").write_text(
        "[Icon Theme]\nName=Yakushi Shake\nComment=Made by yakushi-cursorctl.py for shake to find\n")
    for shape, (names, aliases) in SHAKE_SHAPES.items():
        frames = {}
        for theme_dir in chain:
            src = next((theme_dir / "cursors" / n for n in names if (theme_dir / "cursors" / n).exists()), None)
            frames = xcursor_frames(src.resolve()) if src else {}
            if frames:
                break
        if not frames:
            continue
        images = []
        for target in sizes:
            nominal = next((n for n in sorted(frames) if n >= target), max(frames))
            w, h, xh, yh, px = frames[nominal]
            k = target / nominal
            nw, nh = max(1, round(w * k)), max(1, round(h * k))
            images.append((target, nw, nh, min(nw - 1, round(xh * k)), min(nh - 1, round(yh * k)),
                           px if (nw, nh) == (w, h) else resample(w, h, px, nw, nh)))
        (folder / "cursors" / shape).write_bytes(xcursor_bytes(images))
        for a in aliases:
            os.symlink(shape, folder / "cursors" / a)
    info = {"theme": tid, "base": base, "sizes": sizes}
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / "shake.json").write_text(json.dumps(info))
    return info


# ---- what is in use ------------------------------------------------------------
def lua_env(text: str, key: str) -> str | None:
    m = re.search(r'hl\.env\(\s*"' + key + r'"\s*,\s*"([^"]*)"\s*\)', text)
    if m:
        return m.group(1)
    m = re.search(r'\b' + key + r'\s*=\s*"([^"]*)"', text)
    return m.group(1) if m else None


def read(path: Path) -> str:
    try:
        return path.read_text()
    except OSError:
        return ""


def current() -> str:
    for src in (read(LOCAL), read(HYPR / "hyprland.lua")):
        v = lua_env(src, "XCURSOR_THEME")
        if v:
            return v
    if os.environ.get("XCURSOR_THEME"):
        return os.environ["XCURSOR_THEME"]
    m = re.search(r"^Inherits\s*=\s*(\S+)", read(HOME / ".icons/default/index.theme"), re.M)
    return m.group(1) if m else "Adwaita"


def size() -> int:
    for src in (read(LOCAL), read(HYPR / "hyprland.lua")):
        v = lua_env(src, "XCURSOR_SIZE")
        if v and v.isdigit():
            return int(v)
    v = os.environ.get("XCURSOR_SIZE", "")
    return int(v) if v.isdigit() else 24


# ---- applying ---------------------------------------------------------------------
def run(*cmd: str) -> bool:
    if shutil.which(cmd[0]) is None:
        return False
    try:
        return subprocess.run(cmd, capture_output=True, timeout=5).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def set_ini(path: Path, key: str, value: str) -> None:
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    try:
        cp.read_string(read(path))
    except configparser.Error:
        pass
    if not cp.has_section("Settings"):
        cp.add_section("Settings")
    cp.set("Settings", key, value)
    buf = io.StringIO()
    cp.write(buf, space_around_delimiters=False)
    path.parent.mkdir(parents=True, exist_ok=True)
    write_safely(path, buf.getvalue())


HOLD_DEFAULT, HOLD_MIN, HOLD_MAX = 0.35, 0.1, 3.0


def shake_on() -> bool:
    return re.search(r"^-- shake: on$", read(LOCAL), re.M) is not None


def hold() -> float:
    m = re.search(r"^-- shake-hold: ([\d.]+)$", read(LOCAL), re.M)
    try:
        return min(HOLD_MAX, max(HOLD_MIN, float(m.group(1)))) if m else HOLD_DEFAULT
    except ValueError:
        return HOLD_DEFAULT


def shaker_pid() -> int:
    """the shake helper's pid, only if that process really is the helper (after
    it is gone its pid number can belong to any other program of yours)"""
    try:
        pid = int(SHAKE_PID.read_text())
        if b"yakushi-shake.py" in Path(f"/proc/{pid}/cmdline").read_bytes():
            return pid
    except (OSError, ValueError):
        pass
    return 0


def shaker_running() -> bool:
    return shaker_pid() != 0


def start_shaker() -> None:
    if shaker_running():
        return
    subprocess.Popen([sys.executable, str(SHAKER)], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def stop_shaker() -> None:
    pid = shaker_pid()
    if pid:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass


def write_local(theme: dict | None, tid: str, sz: int, shake: bool, stay: float | None = None) -> None:
    stay = hold() if stay is None else stay
    hypr_kind = bool(theme and theme["kind"] == "hyprcursor")
    lines = [
        "-- Mouse cursor, written by Settings -> Input -> Cursor (yakushi-cursorctl.py).",
        f"-- shake: {'on' if shake else 'off'}",
        f"-- shake-hold: {stay:.2f}",
        f'hl.env("XCURSOR_THEME", "{tid}")',
        f'hl.env("XCURSOR_SIZE", "{sz}")',
    ]
    if hypr_kind:
        lines += [f'hl.env("HYPRCURSOR_THEME", "{tid}")', f'hl.env("HYPRCURSOR_SIZE", "{sz}")']
    HYPR.mkdir(parents=True, exist_ok=True)
    write_safely(LOCAL, "\n".join(lines) + "\n")


def theme_by_id(tid: str) -> dict | None:
    return next((t for t in find_themes() if t["id"] == tid), None)


def push_everywhere(tid: str, sz: int) -> bool:
    live = run("hyprctl", "setcursor", tid, str(sz))
    run("gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", tid)
    run("gsettings", "set", "org.gnome.desktop.interface", "cursor-size", str(sz))
    for v in (3, 4):
        ini = HOME / f".config/gtk-{v}.0/settings.ini"
        set_ini(ini, "gtk-cursor-theme-name", tid)
        set_ini(ini, "gtk-cursor-theme-size", str(sz))
    write_defaults(tid)
    return live


def write_defaults(tid: str) -> None:
    """the "default" theme X11 apps fall back to. Steam (and every Chromium /
    Electron app on X11) ignores XCURSOR_THEME and only looks at "default",
    and ~/.local/share/icons/default wins over ~/.icons/default - Plasma, for
    one, leaves a Breeze one there - so both point at your theme"""
    for base in (HOME / ".local/share/icons", HOME / ".icons"):
        folder = base / "default"
        if folder.is_symlink():                  # a link to some other theme
            folder.unlink()
        cursors = folder / "cursors"
        if cursors.is_symlink():
            cursors.unlink()
        elif cursors.is_dir():                   # its own cursors would win over Inherits
            cursors.rename(folder / "cursors.old")
        folder.mkdir(parents=True, exist_ok=True)
        want = f"[Icon Theme]\nName=Default\nInherits={tid}\n"
        if read(folder / "index.theme") != want:
            (folder / "index.theme").write_text(want)


def apply(theme: dict) -> dict:
    tid, sz = theme["id"], size()
    write_local(theme, tid, sz, shake_on())
    live = push_everywhere(tid, sz)
    if shake_on():
        write_shake_theme()
    msg = f"Cursor: {theme['name']}." + ("" if live else " It applies at the next login.")
    return {"ok": True, "current": tid, "size": sz, "message": msg}


def resize(sz: int) -> dict:
    tid = current()
    write_local(theme_by_id(tid), tid, sz, shake_on())
    live = push_everywhere(tid, sz)
    if shake_on():
        write_shake_theme()
    return {"ok": True, "current": tid, "size": sz,
            "message": f"Cursor size {sz}." + ("" if live else " It applies at the next login.")}


def shake(on: bool) -> dict:
    tid = current()
    write_local(theme_by_id(tid), tid, size(), on)
    if on:
        write_shake_theme()
        start_shaker()
        msg = "Shake the mouse fast: the cursor grows for a moment."
    else:
        stop_shaker()
        msg = "Shake to find is off."
    return {"ok": True, "shake": on, "message": msg}


def listing(**extra) -> dict:
    themes = find_themes()
    for t in themes:
        t["preview"] = preview(t)
    return {"ok": True, "current": current(), "size": size(), "shake": shake_on(), "hold": hold(),
            "themes": themes, **extra}


def login() -> None:
    """Hyprland draws its own pointer with the theme it found when it started,
    before cursor.local.lua is read; set the saved one right away (a few
    tries while Hyprland is still coming up)"""
    if shutil.which("hyprctl") is None:
        return
    import time
    tid, sz = current(), str(size())
    try:
        write_defaults(tid)                      # in case something else changed it
    except OSError:
        pass
    for _ in range(10):
        try:
            out = subprocess.run(["hyprctl", "setcursor", tid, sz],
                                 capture_output=True, text=True, timeout=3).stdout
        except (OSError, subprocess.TimeoutExpired):
            out = ""
        if out.strip() == "ok":
            return
        time.sleep(0.3)


def main() -> None:
    a = sys.argv[1:]
    if a == ["login"]:
        login()
    elif a == ["list"]:
        print(json.dumps(listing()))
    elif len(a) == 2 and a[0] == "set":
        theme = next((t for t in find_themes() if t["id"] == a[1]), None)
        if theme is None:
            print(json.dumps({"ok": False, "message": f"No cursor theme called {a[1]}."}))
            raise SystemExit(1)
        print(json.dumps(apply(theme)))
    elif len(a) == 2 and a[0] == "size" and a[1].isdigit() and 8 <= int(a[1]) <= 128:
        print(json.dumps(resize(int(a[1]))))
    elif len(a) == 2 and a[0] == "hold" and re.fullmatch(r"\d+(\.\d+)?", a[1]):
        stay = min(HOLD_MAX, max(HOLD_MIN, float(a[1])))
        tid = current()
        write_local(theme_by_id(tid), tid, size(), shake_on(), stay)
        print(json.dumps({"ok": True, "hold": stay, "message": f"Stays big for {stay:.1f} s."}))
    elif len(a) == 2 and a[0] == "shake" and a[1] in ("on", "off"):
        print(json.dumps(shake(a[1] == "on")))
    else:
        print(json.dumps({"ok": False, "message": "usage: list | set <theme> | size <px> | shake on|off | hold <seconds> | login"}))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
