#!/usr/bin/env python3
"""Make a coloured copy of an installed cursor theme, on this computer.

    yakushi-cursor-tint.py <theme> [#rrggbb] [new-name]

    yakushi-cursor-tint.py breeze_cursors              -> Breeze-Red
    yakushi-cursor-tint.py Adwaita "#4d8dff" Adwaita-Blue

The dark body of every cursor takes the colour; white edges, shadows and
anything already coloured stay as they are. The copy goes to
~/.local/share/icons/<new-name> and shows up in Settings -> Input -> Cursor.
Nothing is downloaded and the original theme is not touched; the copy stays
on this computer (it is made from your installed theme, so it keeps that
theme's licence).
"""
from __future__ import annotations

import json
import os
import re
import shutil
import struct
import sys
from pathlib import Path

HOME = Path.home()
RED = "#e2202f"


def icon_dirs() -> list[Path]:
    dirs = [HOME / ".local/share/icons", HOME / ".icons"]
    data = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    return dirs + [Path(p) / "icons" for p in data.split(":") if p]


def find_theme(name: str) -> Path | None:
    for d in icon_dirs():
        if (d / name / "cursors").is_dir():
            return d / name
    return None


def display_name(folder: Path) -> str:
    try:
        m = re.search(r"^Name\s*=\s*(.+)$", (folder / "index.theme").read_text(errors="ignore"), re.M)
        return m.group(1).strip() if m else folder.name
    except OSError:
        return folder.name


def make_mapper(hex_colour: str):
    """premultiplied BGRA pixel -> tinted premultiplied BGRA pixel (memoised:
    cursor art reuses few colours, so this stays fast in plain Python)"""
    tr, tg, tb = (int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))
    memo: dict[bytes, bytes] = {}

    def tint(px: bytes) -> bytes:
        out = memo.get(px)
        if out is not None:
            return out
        b, g, r, a = px
        if a == 0:
            out = px
        else:
            r0, g0, b0 = (min(255, c * 255 // a) for c in (r, g, b))
            hi, lo = max(r0, g0, b0), min(r0, g0, b0)
            if hi - lo > 60:                         # already coloured: keep
                out = px
            else:
                light = (0.299 * r0 + 0.587 * g0 + 0.114 * b0) / 255
                # dark -> colour, white -> white; faint (shadow) pixels keep black
                solid = min(1.0, max(0.0, (a / 255 - 0.55) / 0.35))
                nr = tr + (255 - tr) * light
                ng = tg + (255 - tg) * light
                nb = tb + (255 - tb) * light
                nr, ng, nb = (o + (n - o) * solid for o, n in ((r0, nr), (g0, ng), (b0, nb)))
                out = bytes((int(nb * a / 255 + 0.5), int(ng * a / 255 + 0.5),
                             int(nr * a / 255 + 0.5), a))
        memo[px] = out
        return out
    return tint


def tint_file(src: Path, dst: Path, tint) -> None:
    data = bytearray(src.read_bytes())
    if data[:4] != b"Xcur":
        dst.write_bytes(data)
        return
    _, _, ntoc = struct.unpack_from("<III", data, 4)
    for i in range(ntoc):
        typ, _, pos = struct.unpack_from("<III", data, 16 + i * 12)
        if typ != 0xFFFD0002:
            continue
        w, h = struct.unpack_from("<II", data, pos + 16)
        start = pos + 36
        px = bytes(data[start:start + w * h * 4])
        data[start:start + w * h * 4] = b"".join(tint(px[j:j + 4]) for j in range(0, len(px), 4))
    dst.write_bytes(data)


def make_copy(source: str, colour: str = RED, name: str | None = None) -> dict:
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", colour):
        return {"ok": False, "message": f"Not a colour: {colour}"}
    src = find_theme(source)
    if src is None:
        return {"ok": False, "message": f"No cursor theme called {source}."}
    base = re.sub(r"[_ ]?cursors$", "", src.name, flags=re.I)
    name = name or (base[:1].upper() + base[1:] + ("-Red" if colour.lower() == RED else "-" + colour[1:].lower()))
    dst = HOME / ".local/share/icons" / name
    if dst.resolve() == src.resolve():
        return {"ok": False, "message": "Pick another name for the copy."}
    if dst.exists():
        shutil.rmtree(dst)
    (dst / "cursors").mkdir(parents=True)
    tint = make_mapper(colour.lower())
    for entry in sorted((src / "cursors").iterdir()):
        target = dst / "cursors" / entry.name
        if entry.is_symlink():
            os.symlink(os.readlink(entry), target)
        elif entry.is_file():
            tint_file(entry, target, tint)
    pretty = display_name(src) + (" Red" if colour.lower() == RED else f" ({colour.lower()})")
    (dst / "index.theme").write_text(
        f"[Icon Theme]\nName={pretty}\nComment=Coloured copy of {display_name(src)}, made on this computer\n")
    return {"ok": True, "id": name, "name": pretty,
            "message": f"Made {pretty}. It is in the list now."}


def main() -> None:
    a = sys.argv[1:]
    if not a or len(a) > 3:
        print(__doc__.strip())
        raise SystemExit(2)
    r = make_copy(a[0], a[1] if len(a) > 1 else RED, a[2] if len(a) > 2 else None)
    print(json.dumps(r))
    raise SystemExit(0 if r["ok"] else 1)


if __name__ == "__main__":
    main()
