#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ALLOWED = {".png", ".jpg", ".jpeg", ".webp"}
MAX_RESULTS = 250
MAX_SCANNED = 12000

def emit(**data):
    print(json.dumps(data, ensure_ascii=False))

def safe_dir(raw: str) -> Path:
    p = Path(raw).expanduser()
    try:
        p = p.resolve()
    except OSError:
        p = p.absolute()
    if not p.is_dir():
        p = Path.home()
    return p

def item(path: Path, is_dir: bool) -> dict:
    return {
        "name": path.name or str(path),
        "path": str(path),
        "is_dir": is_dir,
        "is_image": (not is_dir and path.suffix.lower() in ALLOWED),
    }

def list_current(base: Path) -> list[dict]:
    rows = []
    try:
        with os.scandir(base) as it:
            entries = list(it)
    except OSError:
        return rows

    dirs = []
    imgs = []
    for ent in entries:
        try:
            if ent.is_dir(follow_symlinks=False):
                dirs.append(Path(ent.path))
            elif ent.is_file(follow_symlinks=False) and Path(ent.name).suffix.lower() in ALLOWED:
                imgs.append(Path(ent.path))
        except OSError:
            continue

    dirs.sort(key=lambda p: p.name.casefold())
    imgs.sort(key=lambda p: p.name.casefold())

    for p in dirs[:MAX_RESULTS]:
        rows.append(item(p, True))
    remaining = MAX_RESULTS - len(rows)
    for p in imgs[:max(0, remaining)]:
        rows.append(item(p, False))
    return rows

def search_recursive(base: Path, query: str) -> list[dict]:
    q = query.casefold().strip()
    if not q:
        return list_current(base)

    rows = []
    scanned = 0

    for root, dirs, files in os.walk(base):
        # Skip common heavy/noisy trees if user searches from HOME.
        dirs[:] = [
            d for d in dirs
            if d not in {".git", "node_modules", ".cache", ".local", "__pycache__"}
        ]

        for name in files:
            scanned += 1
            if scanned > MAX_SCANNED or len(rows) >= MAX_RESULTS:
                return rows

            p = Path(root) / name
            if p.suffix.lower() not in ALLOWED:
                continue
            if q not in name.casefold():
                continue

            rows.append(item(p, False))

    rows.sort(key=lambda x: x["name"].casefold())
    return rows[:MAX_RESULTS]

def main():
    if len(sys.argv) < 2:
        emit(ok=False, message="Missing directory.")
        raise SystemExit(2)

    base = safe_dir(sys.argv[1])
    query = sys.argv[2] if len(sys.argv) >= 3 else ""

    rows = search_recursive(base, query) if query.strip() else list_current(base)

    emit(
        ok=True,
        directory=str(base),
        parent=str(base.parent),
        query=query,
        count=len(rows),
        entries=rows,
    )

if __name__ == "__main__":
    main()
