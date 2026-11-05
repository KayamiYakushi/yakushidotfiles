#!/usr/bin/env python3
"""The login screen (SDDM) background, for Settings -> Login Screen.

    yakushi-sddmctl.py status
    yakushi-sddmctl.py set <image> [--password-stdin]
    yakushi-sddmctl.py reset [--password-stdin]

The picture you choose is turned into a clean PNG here, as you: an image
from the internet is never opened as root. Only that PNG goes to the small
root helper (/usr/local/libexec/yakushi-sddmctl), which checks it is a PNG
and copies it into the theme. With --password-stdin your password is the
first line of stdin (Settings asks for it in the page) and goes to sudo
through a pipe; without it pkexec asks.
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

THEME_DIR = Path("/usr/share/sddm/themes/yakushi")
BACKGROUND = THEME_DIR / "background.png"
ROOT_HELPER = Path("/usr/local/libexec/yakushi-sddmctl")
ALLOWED = {".png", ".jpg", ".jpeg", ".webp"}
MAX_BYTES = 100 * 1024 * 1024
HERE = Path(__file__).resolve().parent

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location("yakushi_taskctl", HERE / "yakushi-taskctl.py")
tasks = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tasks)


def emit(ok=True, **values):
    data = {"ok": ok}
    data.update(values)
    print(json.dumps(data, ensure_ascii=False))


def stop(message, code=1, **values):
    emit(False, message=message, **values)
    raise SystemExit(code)


def source_path(raw):
    parsed = urlparse(raw)
    if parsed.scheme == "file":
        return Path(unquote(parsed.path))
    return Path(raw).expanduser()


def run_root(*args):
    result, err = tasks.as_root([str(ROOT_HELPER), *map(str, args)], 120)
    if result == "ok":
        return
    if result == "wrong":
        stop(tasks.ROOT_MESSAGES["wrong"], wrongPassword=True)
    stop(tasks.ROOT_MESSAGES.get(result) or err or "Could not update SDDM.")


def clean_png(src: Path) -> Path:
    """the picture as a plain PNG, made without root (at most 4K, no metadata)"""
    magick = shutil.which("magick") or shutil.which("convert")
    if magick is None:
        stop("ImageMagick (magick) is not installed.")
    folder = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/yakushi-{os.getuid()}") / "yakushi"
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    out = folder / "sddm-background.png"
    out.unlink(missing_ok=True)
    try:
        proc = subprocess.run(
            [magick, "-limit", "memory", "512MiB", "-limit", "map", "1GiB",
             f"{src}[0]", "-auto-orient", "-strip", "-resize", "3840x3840>", f"PNG24:{out}"],
            capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        stop("The picture took too long to convert.")
    if proc.returncode != 0 or not out.is_file():
        out.unlink(missing_ok=True)
        stop("Could not read that picture (it may be damaged, or not really an image).")
    os.chmod(out, 0o644)
    return out


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
    args = tasks.take_password(sys.argv[1:])
    if not args:
        stop("Missing command.", 2)

    cmd = args[0]

    if cmd == "status":
        status()
        return

    if not ROOT_HELPER.is_file():
        stop("SDDM helper is not installed.")

    if cmd == "set" and len(args) == 2:
        src = source_path(args[1]).resolve()
        if not src.is_file():
            stop("Selected image does not exist.")
        if src.suffix.lower() not in ALLOWED:
            stop("Use PNG, JPG, JPEG or WEBP.")
        if src.stat().st_size > MAX_BYTES:
            stop("The picture is larger than 100 MB.")

        png = clean_png(src)
        try:
            run_root("set-background", png)
        finally:
            png.unlink(missing_ok=True)
        emit(
            True,
            background=True,
            preview=BACKGROUND.as_uri(),
            message="Login background updated. It will appear on the next SDDM login.",
        )
        return

    if cmd == "reset" and len(args) == 1:
        run_root("reset-background")
        emit(
            True,
            background=False,
            preview="",
            message="Login background reset to the default dark Yakushi screen.",
        )
        return

    stop("Invalid command.", 2)


if __name__ == "__main__":
    main()
