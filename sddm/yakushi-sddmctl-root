#!/usr/bin/env python3
"""Root helper for the Yakushi login screen background.

    yakushi-sddmctl set-background <png>
    yakushi-sddmctl reset-background

It never opens a picture with an image library: Settings has already turned
your picture into a plain PNG (as you, without root). Here it is only checked
to really be a PNG of a sane size, then copied into the SDDM theme.
"""
from pathlib import Path
import os
import stat
import sys

THEME_DIR = Path("/usr/share/sddm/themes/yakushi")
BACKGROUND = THEME_DIR / "background.png"
MAX_BYTES = 100 * 1024 * 1024
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def fail(message, code=1):
    print(message, file=sys.stderr)
    raise SystemExit(code)


if os.geteuid() != 0:
    fail("This helper must run as root.")

if len(sys.argv) < 2:
    fail("Missing command.", 2)

cmd = sys.argv[1]

if cmd == "set-background":
    if len(sys.argv) != 3:
        fail("Missing image path.", 2)

    # open it once, without following a symlink, and use only that handle
    try:
        fd = os.open(sys.argv[2], os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError:
        fail("The prepared picture is missing.")
    with os.fdopen(fd, "rb") as src:
        info = os.fstat(src.fileno())
        if not stat.S_ISREG(info.st_mode):
            fail("Not a regular file.")
        if info.st_size > MAX_BYTES:
            fail("Image is larger than 100 MB.")
        data = src.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        fail("Image is larger than 100 MB.")
    if not data.startswith(PNG_SIGNATURE):
        fail("Not a PNG picture.")

    THEME_DIR.mkdir(parents=True, exist_ok=True)
    tmp = THEME_DIR / ".background.png.tmp"
    out = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC, 0o644)
    with os.fdopen(out, "wb") as dst:
        dst.write(data)
        dst.flush()
        os.fsync(dst.fileno())
    os.chmod(tmp, 0o644)
    os.replace(tmp, BACKGROUND)
    print(BACKGROUND)

elif cmd == "reset-background":
    try:
        BACKGROUND.unlink()
    except FileNotFoundError:
        pass
    print("reset")

else:
    fail("Invalid command.", 2)
