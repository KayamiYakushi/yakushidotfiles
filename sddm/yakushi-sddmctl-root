#!/usr/bin/env python3
from pathlib import Path
import os
import shutil
import subprocess
import sys

THEME_DIR = Path("/usr/share/sddm/themes/yakushi")
BACKGROUND = THEME_DIR / "background.png"
ALLOWED = {".png", ".jpg", ".jpeg", ".webp"}
MAX_BYTES = 100 * 1024 * 1024

def fail(message, code=1):
    print(message, file=sys.stderr)
    raise SystemExit(code)

if os.geteuid() != 0:
    fail("This helper must run as root.")

if len(sys.argv) < 2:
    fail("Missing command.", 2)

THEME_DIR.mkdir(parents=True, exist_ok=True)
cmd = sys.argv[1]

if cmd == "set-background":
    if len(sys.argv) != 3:
        fail("Missing image path.", 2)

    src = Path(sys.argv[2]).expanduser().resolve()

    if not src.is_file():
        fail("Selected image does not exist.")
    if src.suffix.lower() not in ALLOWED:
        fail("Unsupported image type.")
    if src.stat().st_size > MAX_BYTES:
        fail("Image is larger than 100 MB.")

    tmp = THEME_DIR / ".background.png.tmp"
    magick = shutil.which("magick")

    if magick:
        proc = subprocess.run(
            [magick, str(src), str(tmp)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if proc.returncode != 0:
            fail((proc.stderr or "Image conversion failed.").strip())
    else:
        shutil.copyfile(src, tmp)

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
