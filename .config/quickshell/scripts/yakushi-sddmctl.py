#!/usr/bin/env python3
import json
from pathlib import Path
import subprocess
import sys
from urllib.parse import unquote, urlparse

THEME_DIR = Path("/usr/share/sddm/themes/yakushi")
BACKGROUND = THEME_DIR / "background.png"
ROOT_HELPER = Path("/usr/local/libexec/yakushi-sddmctl")
DROPIN = Path("/etc/sddm.conf.d/99-yakushi-theme.conf")
ALLOWED = {".png", ".jpg", ".jpeg", ".webp"}

def emit(ok=True, **values):
    data = {"ok": ok}
    data.update(values)
    print(json.dumps(data, ensure_ascii=False))

def source_path(raw):
    parsed = urlparse(raw)
    if parsed.scheme == "file":
        return Path(unquote(parsed.path))
    return Path(raw).expanduser()

def run_root(*args):
    proc = subprocess.run(
        ["pkexec", str(ROOT_HELPER), *map(str, args)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        if proc.returncode in (126, 127):
            detail = "Authorization was cancelled."
        emit(False, message=detail or "Could not update SDDM.")
        raise SystemExit(proc.returncode)

def status():
    installed = THEME_DIR.is_dir() and ROOT_HELPER.is_file()
    background = BACKGROUND.is_file()
    emit(
        True,
        installed=installed,
        background=background,
        preview=BACKGROUND.as_uri() if background else "",
        message="Yakushi SDDM theme is ready." if installed else "Yakushi SDDM theme is not installed.",
    )

def main():
    if len(sys.argv) < 2:
        emit(False, message="Missing command.")
        raise SystemExit(2)

    cmd = sys.argv[1]

    if cmd == "status":
        status()
        return

    if not ROOT_HELPER.is_file():
        emit(False, message="SDDM helper is not installed.")
        raise SystemExit(1)

    if cmd == "set" and len(sys.argv) == 3:
        src = source_path(sys.argv[2]).resolve()
        if not src.is_file():
            emit(False, message="Selected image does not exist.")
            raise SystemExit(1)
        if src.suffix.lower() not in ALLOWED:
            emit(False, message="Use PNG, JPG, JPEG or WEBP.")
            raise SystemExit(1)

        run_root("set-background", src)
        emit(
            True,
            background=True,
            preview=BACKGROUND.as_uri(),
            message="Login background updated. It will appear on the next SDDM login.",
        )
        return

    if cmd == "reset":
        run_root("reset-background")
        emit(
            True,
            background=False,
            preview="",
            message="Login background reset to the default dark Yakushi screen.",
        )
        return

    emit(False, message="Invalid command.")
    raise SystemExit(2)

if __name__ == "__main__":
    main()
