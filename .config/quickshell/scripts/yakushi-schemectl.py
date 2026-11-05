#!/usr/bin/env python3
"""Light or dark apps, for Settings -> Appearance -> Apps.

    yakushi-schemectl.py get          {"scheme": "dark"|"light", ...}
    yakushi-schemectl.py set dark|light

`set` writes the same choice everywhere apps look for it:
  * GSettings org.gnome.desktop.interface color-scheme  (libadwaita / GTK4
    apps such as Files read it through xdg-desktop-portal-gtk, Firefox and
    Qt 6 apps through the same portal)
  * GSettings gtk-theme: Adwaita <-> Adwaita-dark, or <theme> <-> <theme>-dark
    when your GTK theme has such a twin (GTK3 apps)
  * gtk-application-prefer-dark-theme (+ gtk-theme-name for GTK3) in
    ~/.config/gtk-3.0/settings.ini and ~/.config/gtk-4.0/settings.ini
Open apps switch on the spot where the toolkit allows it. Runs only when
called.
"""
from __future__ import annotations

import configparser
import io
import json
import os
import shutil
import subprocess
import sys
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
SCHEMA = "org.gnome.desktop.interface"
INI = {
    3: HOME / ".config/gtk-3.0/settings.ini",
    4: HOME / ".config/gtk-4.0/settings.ini",
}
THEME_DIRS = [HOME / ".themes", HOME / ".local/share/themes", Path("/usr/share/themes")]


def gsettings(*args: str) -> str | None:
    if shutil.which("gsettings") is None:
        return None
    try:
        p = subprocess.run(["gsettings", *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return p.stdout.strip().strip("'") if p.returncode == 0 else None


def has_portal() -> bool:
    """libadwaita apps only see the choice through a Settings portal."""
    for d in (Path("/usr/share/xdg-desktop-portal/portals"),):
        for name in ("gtk.portal", "gnome.portal", "kde.portal"):
            if (d / name).exists():
                return True
    return False


def theme_exists(name: str) -> bool:
    if name in ("Adwaita", "Adwaita-dark", "HighContrast", "HighContrastInverse"):
        return True          # built into GTK3
    return any((d / name / "gtk-3.0").is_dir() for d in THEME_DIRS)


def twin(theme: str, dark: bool) -> str:
    """The light/dark sibling of a GTK3 theme, or the theme itself."""
    if not theme:
        return "Adwaita-dark" if dark else "Adwaita"
    for suffix in ("-dark", "-Dark", "_dark"):
        if theme.endswith(suffix):
            base = theme[: -len(suffix)]
            return theme if dark else (base if theme_exists(base) else theme)
    if dark:
        for suffix in ("-dark", "-Dark"):
            if theme_exists(theme + suffix):
                return theme + suffix
    return theme


def current() -> str:
    # our own record first (written by `set`), then what GNOME settings say
    v = read_ini(INI[3]).get("Settings", "gtk-application-prefer-dark-theme", fallback="").lower()
    if v in ("1", "true", "0", "false"):
        return "dark" if v in ("1", "true") else "light"
    cs = gsettings("get", SCHEMA, "color-scheme")
    return "light" if cs in ("prefer-light", "default") else "dark"


def read_ini(path: Path) -> configparser.ConfigParser:
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str          # keep key case
    try:
        cp.read_string(path.read_text())
    except (OSError, configparser.Error):
        pass
    if not cp.has_section("Settings"):
        cp.add_section("Settings")
    return cp


def write_ini(path: Path, values: dict[str, str]) -> None:
    cp = read_ini(path)
    for k, v in values.items():
        cp.set("Settings", k, v)
    out = io.StringIO()
    cp.write(out, space_around_delimiters=False)
    path.parent.mkdir(parents=True, exist_ok=True)
    write_safely(path, out.getvalue())


def state(**extra) -> dict:
    return {
        "ok": True,
        "scheme": current(),
        "gsettings": gsettings("get", SCHEMA, "color-scheme") is not None,
        "portal": has_portal(),
        **extra,
    }


def apply(scheme: str) -> dict:
    dark = scheme == "dark"
    notes = []

    have_gs = gsettings("get", SCHEMA, "color-scheme") is not None
    if have_gs:
        if gsettings("set", SCHEMA, "color-scheme", "prefer-dark" if dark else "prefer-light") is None:
            gsettings("set", SCHEMA, "color-scheme", "prefer-dark" if dark else "default")
        theme = gsettings("get", SCHEMA, "gtk-theme") or ""
        new_theme = twin(theme, dark)
        if new_theme != theme:
            gsettings("set", SCHEMA, "gtk-theme", new_theme)
    else:
        theme = read_ini(INI[3]).get("Settings", "gtk-theme-name", fallback="")
        new_theme = twin(theme, dark)
        notes.append("gsettings is missing: only settings.ini was changed (apps pick it up when reopened).")

    flag = "true" if dark else "false"
    write_ini(INI[3], {"gtk-application-prefer-dark-theme": flag, "gtk-theme-name": new_theme})
    write_ini(INI[4], {"gtk-application-prefer-dark-theme": flag})

    if not has_portal():
        notes.append("Install xdg-desktop-portal-gtk so Files and other GTK4 apps follow too.")
    return state(message=" ".join(notes) or ("Apps are dark now." if dark else "Apps are light now."))


def main() -> None:
    a = sys.argv[1:]
    if a == ["get"]:
        print(json.dumps(state()))
    elif len(a) == 2 and a[0] == "set" and a[1] in ("dark", "light"):
        print(json.dumps(apply(a[1])))
    else:
        print(json.dumps({"ok": False, "message": "usage: get | set dark|light"}))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
