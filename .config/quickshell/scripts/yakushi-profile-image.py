#!/usr/bin/env python3
from pathlib import Path
import shutil
import sys

if len(sys.argv) != 2:
    raise SystemExit("Usage: yakushi-profile-image.py <image>")

src = Path(sys.argv[1]).expanduser()

if not src.is_file():
    raise SystemExit(f"Not a file: {src}")

dst = Path.home() / ".config" / "quickshell" / "assets" / "system-profile"
dst.parent.mkdir(parents=True, exist_ok=True)

tmp = dst.with_name(dst.name + ".tmp")
shutil.copyfile(src, tmp)
tmp.replace(dst)

print(dst)
