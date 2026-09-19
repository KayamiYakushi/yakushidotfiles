#!/usr/bin/env python3
from pathlib import Path
import hashlib

home = Path.home()
root = home / "Documents"
index = home / ".cache" / "quickshell" / "wallpaper-index"

index.mkdir(parents=True, exist_ok=True)

exts = {".jpg", ".jpeg", ".png", ".webp"}
wanted = {}

if root.exists():
    for p in root.rglob("*"):
        try:
            if not p.is_file():
                continue
        except OSError:
            continue

        if p.suffix.lower() not in exts:
            continue

        digest = hashlib.sha1(str(p).encode()).hexdigest()[:12]
        safe_stem = p.stem[:80].replace("/", "_")
        name = f"{safe_stem}-{digest}{p.suffix.lower()}"
        wanted[name] = p

# Remove stale links/files from the generated index.
for entry in index.iterdir():
    if entry.name not in wanted:
        try:
            entry.unlink()
        except OSError:
            pass

# Create stable symlinks to the real files in Documents.
for name, src in wanted.items():
    dst = index / name

    if dst.is_symlink():
        try:
            if dst.resolve() == src.resolve():
                continue
        except OSError:
            pass
        dst.unlink(missing_ok=True)
    elif dst.exists():
        dst.unlink()

    try:
        dst.symlink_to(src)
    except OSError:
        pass

print(len(wanted))
