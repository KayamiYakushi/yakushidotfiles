#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path

HWMON_ROOT = Path("/sys/class/hwmon")
OUT = Path.home() / ".config/waybar/hardware.local.jsonc"

CPU_DRIVERS = ("k10temp", "zenpower", "coretemp", "cpu_thermal")
CPU_LABEL_PRIORITY = ("Tctl", "Package id 0", "Tdie", "CPU")
GPU_DRIVERS = ("amdgpu",)
GPU_LABEL_PRIORITY = ("edge", "junction", "mem")


def read_text(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def sensors_for(hwmon: Path):
    result = []
    for input_path in sorted(hwmon.glob("temp*_input")):
        stem = input_path.name.removesuffix("_input")
        label = read_text(hwmon / f"{stem}_label")
        result.append((input_path.name, label))
    return result


def choose_sensor(drivers, label_priority):
    matches = []

    for hwmon in sorted(HWMON_ROOT.glob("hwmon*")):
        name = read_text(hwmon / "name")
        if name not in drivers:
            continue

        entries = sensors_for(hwmon)
        if not entries:
            continue

        real_hwmon = Path(os.path.realpath(hwmon))
        hwmon_abs = real_hwmon.parent

        for wanted in label_priority:
            for filename, label in entries:
                if label == wanted:
                    return {
                        "driver": name,
                        "label": label,
                        "hwmon_path_abs": str(hwmon_abs),
                        "input_filename": filename,
                    }

        filename, label = entries[0]
        matches.append(
            {
                "driver": name,
                "label": label or filename,
                "hwmon_path_abs": str(hwmon_abs),
                "input_filename": filename,
            }
        )

    return matches[0] if matches else None


def module(sensor, prefix):
    if sensor is None:
        return {
            "format": "",
            "tooltip": False,
            "interval": 30,
        }

    return {
        "hwmon-path-abs": sensor["hwmon_path_abs"],
        "input-filename": sensor["input_filename"],
        "interval": 5,
        "format": f"{prefix} {{temperatureC}}°C",
        "tooltip": False,
    }


cpu = choose_sensor(CPU_DRIVERS, CPU_LABEL_PRIORITY)
gpu = choose_sensor(GPU_DRIVERS, GPU_LABEL_PRIORITY)

config = {
    "temperature#cpu": module(cpu, "CPU"),
    "temperature#gpu": module(gpu, "GPU"),
}

OUT.parent.mkdir(parents=True, exist_ok=True)
tmp = OUT.with_suffix(".jsonc.tmp")
tmp.write_text(json.dumps(config, indent=4) + "\n")
tmp.replace(OUT)

print(f"Generated: {OUT}")
if cpu:
    print("CPU:", f'{cpu["driver"]} / {cpu["label"]} / {cpu["input_filename"]}')
else:
    print("CPU: no supported hwmon sensor found")

if gpu:
    print("GPU:", f'{gpu["driver"]} / {gpu["label"]} / {gpu["input_filename"]}')
else:
    print("GPU: no supported hwmon sensor found")
