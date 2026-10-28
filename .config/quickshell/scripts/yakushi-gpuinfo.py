#!/usr/bin/env python3
"""Exact GPU model + where to read its usage, for Settings -> System.

Prints one JSON object:
    name        marketing name, e.g. "AMD Radeon RX 9060 XT"
    busy        sysfs file with the GPU load in % (AMD / Intel xe), or ""
    vramUsed    sysfs file with used VRAM in bytes (AMD), or ""
    vramTotal   sysfs file with total VRAM in bytes (AMD), or ""
    nvidia      true when usage has to come from nvidia-smi

lspci only knows the chip family ("Navi 44 [Radeon RX 9050 / 9060 XT]");
the exact name comes from libdrm's amdgpu.ids (device + revision id) for
AMD, from the driver for NVIDIA, and from lspci otherwise. Runs once, when
the System page opens.
"""
import json
import re
import shutil
import subprocess
from pathlib import Path

IDS_FILES = (
    Path("/usr/share/libdrm/amdgpu.ids"),
    Path("/usr/local/share/libdrm/amdgpu.ids"),
)


def read(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def gpu_devices():
    """(card dir, device dir) for every DRM card, the boot GPU first."""
    cards = []
    for card in sorted(Path("/sys/class/drm").glob("card[0-9]*")):
        if "-" in card.name:
            continue                       # connectors like card1-DP-1
        dev = card / "device"
        if not (dev / "vendor").exists():
            continue
        boot = read(dev / "boot_vga") == "1"
        cards.append((not boot, card.name, card, dev))
    cards.sort()
    return [(c, d) for _, _, c, d in cards]


def amd_name(dev: Path) -> str:
    device = read(dev / "device").lower().removeprefix("0x").upper()
    revision = read(dev / "revision").lower().removeprefix("0x").upper()
    if not device:
        return ""
    for ids in IDS_FILES:
        try:
            lines = ids.read_text().splitlines()
        except OSError:
            continue
        fallback = ""
        for line in lines:
            parts = [p.strip() for p in line.split(",", 2)]
            if len(parts) != 3 or parts[0].upper() != device:
                continue
            if parts[1].upper().zfill(2) == revision.zfill(2):
                return parts[2]
            fallback = fallback or parts[2]
        if fallback:
            return fallback
    return ""


def nvidia_name() -> str:
    for info in Path("/proc/driver/nvidia/gpus").glob("*/information"):
        match = re.search(r"^Model:\s*(.+)$", read(info), re.M)
        if match:
            return match.group(1).strip()
    if shutil.which("nvidia-smi"):
        try:
            out = subprocess.run(["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
                                 capture_output=True, text=True, timeout=5).stdout
            if out.strip():
                return out.strip().splitlines()[0]
        except (OSError, subprocess.TimeoutExpired):
            pass
    return ""


def lspci_name(dev: Path) -> str:
    slot = dev.resolve().name                       # e.g. 0000:03:00.0
    try:
        out = subprocess.run(["lspci", "-s", slot], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""
    text = out.split(": ", 1)[-1].strip()
    text = re.sub(r"\s*\(rev [0-9a-f]+\)$", "", text)
    # "Advanced Micro Devices, Inc. [AMD/ATI] Navi 44 [Radeon RX 9060 XT]"
    bracket = re.findall(r"\[([^\]]+)\]", text)
    if bracket and not bracket[-1].startswith(("AMD/ATI", "AMD")):
        vendor = "AMD" if "AMD" in text else "NVIDIA" if "NVIDIA" in text else ""
        return (vendor + " " + bracket[-1]).strip()
    return text


def main() -> None:
    result = {"name": "", "busy": "", "vramUsed": "", "vramTotal": "", "nvidia": False}
    for card, dev in gpu_devices():
        vendor = read(dev / "vendor").lower()
        name = ""
        if vendor == "0x1002":                       # AMD
            name = amd_name(dev)
            for key, file in (("vramUsed", "mem_info_vram_used"), ("vramTotal", "mem_info_vram_total")):
                if (dev / file).exists():
                    result[key] = str(dev / file)
        elif vendor == "0x10de":                     # NVIDIA
            name = nvidia_name()
            result["nvidia"] = shutil.which("nvidia-smi") is not None
        if (dev / "gpu_busy_percent").exists():
            result["busy"] = str(dev / "gpu_busy_percent")
        result["name"] = name or lspci_name(dev) or "Unknown GPU"
        break
    if not result["name"]:
        result["name"] = "Unknown GPU"
    print(json.dumps(result))


if __name__ == "__main__":
    main()
