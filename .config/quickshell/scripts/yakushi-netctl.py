#!/usr/bin/env python3
"""Ethernet and Wi-Fi for Settings -> Network (through NetworkManager's nmcli).

Commands (each prints one JSON object):
    state                   cables, Wi-Fi radio, the networks seen now, and
                            which connection carries the internet
    scan                    ask for a fresh Wi-Fi scan first, then `state`
    radio on|off            switch Wi-Fi
    join <ssid>             connect to a Wi-Fi network; with --password-stdin
                            the password is the first line of stdin (Settings
                            sends it that way: a command line can be read by
                            any program on the computer, stdin cannot)
    up <uuid>               connect a saved connection (no password needed)
    down <uuid>             disconnect that connection
    wired <device> up|down  connect / disconnect a cable
    details <uuid>          settings of a connection + what it uses right now
    apply <uuid> <json>     change them, e.g. {"dnsMode": "custom", "dns":
                            ["1.1.1.1"], "ipMode": "auto", "autoconnect": true}
    forget <uuid>           delete a saved connection (its Wi-Fi password too)
    speedtest               measure ping, download and upload (about 20 s,
                            Cloudflare's speed test servers); kept in history
    speed                   the last result and the average of the history

A Wi-Fi network seen through several access points is listed once, with the
strongest signal; the connected one comes first. Changes to an active
connection are applied right away (nmcli device reapply). Nothing runs in
the background: this is called by the Settings page only.
"""
from __future__ import annotations

import ipaddress
import json
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
HISTORY = HOME / ".cache/yakushi/speedtest.json"
KEEP = 10                     # speed tests kept for the average
TYPES = {"802-3-ethernet": "ethernet", "802-11-wireless": "wifi"}


# ---- nmcli ---------------------------------------------------------------------
def nmcli(*args: str, timeout: int = 30, given: str | None = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(["nmcli", *args], capture_output=True, text=True, timeout=timeout,
                              input=given if given is not None else "")
    except FileNotFoundError:
        return subprocess.CompletedProcess(args, 127, "", "nmcli is not installed")
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, "", "nmcli timed out")


def join(ssid: str, password: str | None) -> subprocess.CompletedProcess:
    """connect to a Wi-Fi network. The password goes to nmcli through its
    --ask prompt on stdin, so it never shows up in the process list."""
    if not password:
        return nmcli("device", "wifi", "connect", ssid, timeout=60)
    res = nmcli("--ask", "device", "wifi", "connect", ssid, timeout=60, given=password + "\n")
    said = res.stdout + res.stderr
    if res.returncode != 0 and "assword" not in said and "required to access" not in said:
        # this nmcli never asked (so the password was not even tried): the plain way
        res = nmcli("device", "wifi", "connect", ssid, "password", password, timeout=60)
    return res


def error_of(res: subprocess.CompletedProcess, fallback: str) -> str:
    lines = [l for l in (res.stderr or "").strip().splitlines() if l.strip()]
    return lines[-1].removeprefix("Error: ").strip() if lines else fallback


def split_terse(line: str, fields: int) -> list[str]:
    """nmcli -t separates with ':' and writes a ':' inside a value as '\\:'."""
    out, cur, i = [], [], 0
    while i < len(line):
        c = line[i]
        if c == "\\" and i + 1 < len(line):
            cur.append(line[i + 1])
            i += 2
            continue
        if c == ":" and len(out) < fields - 1:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return out


def fields(text: str) -> dict[str, list[str]]:
    """`nmcli -t -f ... show` output -> {field: [values]} (IP4.ADDRESS[1] -> IP4.ADDRESS)"""
    out: dict[str, list[str]] = {}
    for line in text.splitlines():
        key, sep, value = line.partition(":")
        if not sep:
            continue
        key = key.split("[", 1)[0]
        value = value.replace("\\:", ":").strip()
        if value and value != "--":
            out.setdefault(key, []).append(value)
    return out


def one(f: dict[str, list[str]], key: str, default: str = "") -> str:
    return (f.get(key) or [default])[0]


def sysfs(dev: str, name: str) -> str:
    try:
        return (Path("/sys/class/net") / dev / name).read_text().strip()
    except OSError:
        return ""


def default_device() -> str:
    """the interface of the default route (the one the internet goes through)"""
    best, metric = "", None
    try:
        lines = Path("/proc/net/route").read_text().splitlines()[1:]
    except OSError:
        return ""
    for line in lines:
        # Iface Destination Gateway Flags RefCnt Use Metric Mask ...
        p = line.split()
        if len(p) > 7 and p[1] == "00000000" and p[7] == "00000000":
            m = int(p[6]) if p[6].isdigit() else 0
            if metric is None or m < metric:
                best, metric = p[0], m
    return best


# ---- what is there -----------------------------------------------------------------
def devices() -> list[dict]:
    res = nmcli("-t", "-f", "DEVICE,TYPE,STATE,CON-UUID,CONNECTION", "device")
    out = []
    for line in res.stdout.splitlines():
        p = split_terse(line.strip(), 5)
        if len(p) == 5 and p[1] in ("ethernet", "wifi"):
            out.append({"device": p[0], "type": p[1], "state": p[2].split(" ")[0],
                        "uuid": p[3], "connection": p[4]})
    return out


def saved_wifi() -> dict[str, str]:
    """ssid -> uuid of the saved Wi-Fi connections"""
    res = nmcli("-t", "-f", "UUID,TYPE", "connection", "show")
    known: dict[str, str] = {}
    for line in res.stdout.splitlines():
        p = split_terse(line.strip(), 2)
        if len(p) == 2 and p[1] == "802-11-wireless":
            ssid = nmcli("-g", "802-11-wireless.ssid", "connection", "show", p[0]).stdout.strip()
            if ssid:
                known.setdefault(ssid.replace("\\:", ":"), p[0])
    return known


def radio_on() -> bool:
    return nmcli("radio", "wifi").stdout.strip() == "enabled"


def networks(known: dict[str, str], active_uuid: str) -> list[dict]:
    res = nmcli("-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY,RATE", "device", "wifi", "list", "--rescan", "no")
    best: dict[str, dict] = {}
    for line in res.stdout.splitlines():
        parts = split_terse(line.strip(), 5)
        if len(parts) != 5 or not parts[1]:
            continue
        in_use, ssid, signal, security, rate = parts
        net = {
            "ssid": ssid,
            "signal": int(signal) if signal.isdigit() else 0,
            "secured": security not in ("", "--"),
            "connected": in_use.strip() == "*",
            "rate": rate.strip() if in_use.strip() == "*" else "",
        }
        old = best.get(ssid)
        if old is None:
            best[ssid] = net
        else:
            if net["connected"]:
                old["rate"] = net["rate"]
            old["connected"] = old["connected"] or net["connected"]
            old["signal"] = max(old["signal"], net["signal"])
            old["secured"] = old["secured"] or net["secured"]
    for net in best.values():
        net["uuid"] = (active_uuid if net["connected"] else "") or known.get(net["ssid"], "")
        net["known"] = bool(net["uuid"])
    return sorted(best.values(), key=lambda n: (not n["connected"], not n["known"], -n["signal"], n["ssid"].lower()))


def wired_entry(d: dict, addrs: dict[str, str]) -> dict:
    speed = sysfs(d["device"], "speed")
    return {
        "device": d["device"],
        "state": d["state"],                          # connected / disconnected / unavailable (no cable)
        "connected": d["state"] == "connected",
        "cable": sysfs(d["device"], "carrier") == "1",
        "connection": d["connection"] if d["connection"] != "--" else "",
        "uuid": d["uuid"] if d["uuid"] != "--" else "",
        "speed": int(speed) if speed.lstrip("-").isdigit() and int(speed) > 0 else 0,
        "ip": addrs.get(d["device"], ""),
        "mac": sysfs(d["device"], "address"),
    }


def addresses() -> dict[str, str]:
    res = nmcli("-t", "-f", "GENERAL.DEVICE,IP4.ADDRESS", "device", "show")
    out, dev = {}, ""
    for line in res.stdout.splitlines():
        key, _, value = line.partition(":")
        if key == "GENERAL.DEVICE":
            dev = value
        elif key.startswith("IP4.ADDRESS") and dev and dev not in out and value:
            out[dev] = value.split("/")[0]
    return out


def state(**extra) -> None:
    devs = devices()
    addrs = addresses()
    wifi_dev = next((d for d in devs if d["type"] == "wifi"), None)
    on = radio_on() if wifi_dev else False
    active = next((d["uuid"] for d in devs if d["type"] == "wifi" and d["state"] == "connected"), "")
    nets = networks(saved_wifi(), active if active != "--" else "") if on else []
    wired = [wired_entry(d, addrs) for d in devs if d["type"] == "ethernet"]

    route = default_device()
    primary = None
    for d in devs:
        if d["device"] == route and d["state"] == "connected":
            primary = {"device": d["device"], "type": d["type"], "name": d["connection"],
                       "uuid": d["uuid"], "ip": addrs.get(d["device"], "")}
            if d["type"] == "ethernet":
                w = next((w for w in wired if w["device"] == d["device"]), None)
                primary["speed"] = f"{w['speed']} Mb/s" if w and w["speed"] else ""
            else:
                n = next((n for n in nets if n["connected"]), None)
                primary["speed"] = n["rate"] if n else ""
                primary["signal"] = n["signal"] if n else 0
    if primary is None and route:
        primary = {"device": route, "type": "other", "name": route, "uuid": "", "ip": addrs.get(route, ""), "speed": ""}
    print(json.dumps({"ok": True, "radio": on, "wifiDevice": wifi_dev["device"] if wifi_dev else "",
                      "wired": wired, "networks": nets, "primary": primary, **extra}))


# ---- one connection ---------------------------------------------------------------
SETTINGS = ("connection.id,connection.uuid,connection.type,connection.autoconnect,"
            "ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.ignore-auto-dns,"
            "ipv6.method,ipv6.dns,GENERAL.DEVICES")


def details(uuid: str) -> dict | None:
    res = nmcli("-t", "-f", SETTINGS, "connection", "show", uuid)
    if res.returncode != 0:
        # GENERAL.* only exists for active connections: ask again without it
        res = nmcli("-t", "-f", SETTINGS.rsplit(",", 1)[0], "connection", "show", uuid)
        if res.returncode != 0:
            return None
    f = fields(res.stdout)
    dev = one(f, "GENERAL.DEVICES")
    dns = [s.strip() for v in f.get("ipv4.dns", []) + f.get("ipv6.dns", []) for s in v.split(",") if s.strip()]
    out = {
        "uuid": one(f, "connection.uuid", uuid),
        "name": one(f, "connection.id"),
        "type": TYPES.get(one(f, "connection.type"), one(f, "connection.type")),
        "device": dev,
        "active": bool(dev),
        "autoconnect": one(f, "connection.autoconnect", "yes") == "yes",
        "ipMode": "manual" if one(f, "ipv4.method") == "manual" else "auto",
        "address": one(f, "ipv4.addresses").split(",")[0].strip(),
        "gateway": one(f, "ipv4.gateway"),
        "dnsMode": "custom" if dns else "auto",
        "dns": dns,
        "ipv6": one(f, "ipv6.method", "auto"),
        "now": {},
    }
    if dev:
        live = fields(nmcli("-t", "-f", "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,IP6.DNS,GENERAL.HWADDR",
                            "device", "show", dev).stdout)
        speed = sysfs(dev, "speed")
        out["now"] = {
            "ip": live.get("IP4.ADDRESS", []),
            "gateway": one(live, "IP4.GATEWAY"),
            "dns": live.get("IP4.DNS", []) + live.get("IP6.DNS", []),
            "ip6": [a for a in live.get("IP6.ADDRESS", []) if not a.lower().startswith("fe80")],
            "mac": one(live, "GENERAL.HWADDR") or sysfs(dev, "address"),
            "speed": f"{speed} Mb/s" if speed.isdigit() and int(speed) > 0 else "",
        }
    return out


def parse_dns(value) -> list[str]:
    items = value if isinstance(value, list) else str(value or "").replace(",", " ").split()
    out = []
    for item in items:
        ip = ipaddress.ip_address(str(item).strip())       # ValueError if not an address
        if str(ip) not in out:
            out.append(str(ip))
    return out


def apply(uuid: str, wanted: dict) -> tuple[bool, str]:
    have = details(uuid)
    if have is None:
        return False, "That connection is gone."
    mods: list[str] = []
    v6_on = have["ipv6"] in ("auto", "dhcp", "manual")

    if "autoconnect" in wanted:
        mods += ["connection.autoconnect", "yes" if wanted["autoconnect"] else "no"]

    ip_mode = wanted.get("ipMode", have["ipMode"])
    dns_mode = wanted.get("dnsMode", have["dnsMode"])
    if ip_mode == "manual" and dns_mode == "auto":
        return False, "A manual address gets no DNS from the router: pick DNS servers too."
    runtime = "ipMode" in wanted or "dnsMode" in wanted      # needs a reapply
    if "ipMode" not in wanted:
        pass
    elif ip_mode == "manual":
        try:
            raw = str(wanted.get("address", have["address"])).strip()
            addr = ipaddress.ip_interface(raw if "/" in raw else raw + "/24")
            gw = str(wanted.get("gateway", have["gateway"]) or "").strip()
            gateway = ipaddress.ip_address(gw) if gw else None
        except ValueError:
            return False, "That is not an IP address (like 192.168.1.50/24)."
        if addr.version != 4 or (gateway and gateway.version != 4):
            return False, "Use an IPv4 address here, like 192.168.1.50/24."
        if gateway and gateway not in addr.network:
            return False, f"The gateway {gateway} is outside {addr.network}."
        mods += ["ipv4.method", "manual", "ipv4.addresses", str(addr), "ipv4.gateway", str(gateway or "")]
    elif ip_mode == "auto":
        mods += ["ipv4.method", "auto", "ipv4.addresses", "", "ipv4.gateway", ""]

    if "dnsMode" not in wanted:
        pass
    elif dns_mode == "custom":
        try:
            servers = parse_dns(wanted.get("dns", have["dns"]))
        except ValueError:
            return False, "One of the DNS servers is not an IP address."
        v4 = [s for s in servers if ipaddress.ip_address(s).version == 4]
        v6 = [s for s in servers if ipaddress.ip_address(s).version == 6]
        if not v4 and not (v6 and v6_on):
            return False, "Give at least one DNS server."
        mods += ["ipv4.dns", " ".join(v4), "ipv4.ignore-auto-dns", "yes"]
        if v6_on:
            mods += ["ipv6.dns", " ".join(v6), "ipv6.ignore-auto-dns", "yes"]
    elif dns_mode == "auto":
        mods += ["ipv4.dns", "", "ipv4.ignore-auto-dns", "no"]
        if v6_on:
            mods += ["ipv6.dns", "", "ipv6.ignore-auto-dns", "no"]

    if not mods:
        return True, "Nothing to change."
    res = nmcli("connection", "modify", uuid, *mods)
    if res.returncode != 0:
        return False, error_of(res, "NetworkManager did not take the change.")
    if have["active"] and runtime:
        dev = have["device"].split(",")[0]
        if nmcli("device", "reapply", dev, timeout=40).returncode != 0:
            res = nmcli("connection", "up", uuid, timeout=60)
            if res.returncode != 0:
                return False, "Saved, but reconnecting failed: " + error_of(res, "unknown error")
        return True, f"Saved and applied to {have['name']}."
    if have["active"] or not runtime:
        return True, "Saved."
    return True, f"Saved for {have['name']}; used the next time it connects."


# ---- speed test --------------------------------------------------------------------
HOST = "speed.cloudflare.com"
AGENT = "yakushi-settings/1"


def _conn():
    import http.client
    import ssl
    return http.client.HTTPSConnection(HOST, timeout=10, context=ssl.create_default_context())


def _ping() -> float:
    conn = _conn()
    times = []
    try:
        for i in range(6):
            t = time.perf_counter()
            conn.request("GET", "/__down?bytes=0", headers={"User-Agent": AGENT})
            conn.getresponse().read()
            if i:                                    # the first one includes TLS setup
                times.append((time.perf_counter() - t) * 1000)
    finally:
        conn.close()
    times.sort()
    return times[len(times) // 2]


def _run_threads(work, seconds: float, streams: int = 4) -> float:
    """run `work(deadline, counter)` in parallel; Mbit/s after a short ramp-up"""
    import threading
    counter = [0]
    lock = threading.Lock()

    def add(n: int) -> None:
        with lock:
            counter[0] += n

    start = time.perf_counter()
    deadline = start + seconds
    threads = [threading.Thread(target=work, args=(deadline, add), daemon=True) for _ in range(streams)]
    for t in threads:
        t.start()
    ramp = 1.5
    time.sleep(ramp)
    with lock:
        base, t0 = counter[0], time.perf_counter()
    for t in threads:
        t.join(seconds + 12)
    with lock:
        total, t1 = counter[0], min(time.perf_counter(), deadline + 1)
    moved = total - base
    if moved <= 0 or t1 <= t0:
        moved, t0 = total, start
    return moved * 8 / max(0.001, t1 - t0) / 1e6


LIMIT_DOWN = 400 * 1024 * 1024   # stop early on very fast lines: data used stays small
LIMIT_UP = 120 * 1024 * 1024


def _download(deadline: float, add) -> None:
    got = 0
    try:
        conn = _conn()
        while time.perf_counter() < deadline and got < LIMIT_DOWN // 4:
            conn.request("GET", "/__down?bytes=25000000", headers={"User-Agent": AGENT})
            r = conn.getresponse()
            while time.perf_counter() < deadline:
                chunk = r.read(65536)
                if not chunk:
                    break
                got += len(chunk)
                add(len(chunk))
            else:
                break
        conn.close()
    except OSError:
        pass


def _upload(deadline: float, add) -> None:
    block = b"0" * 65536
    size = 8 * 1024 * 1024
    sent = 0
    try:
        conn = _conn()
        while time.perf_counter() < deadline and sent < LIMIT_UP // 4:
            conn.putrequest("POST", "/__up")
            conn.putheader("User-Agent", AGENT)
            conn.putheader("Content-Type", "application/octet-stream")
            conn.putheader("Content-Length", str(size))
            conn.endheaders()
            done = 0
            while done < size and time.perf_counter() < deadline:
                conn.send(block)
                done += len(block)
                sent += len(block)
                add(len(block))
            if done < size:
                break
            conn.getresponse().read()
        conn.close()
    except OSError:
        pass


def history() -> list[dict]:
    try:
        data = json.loads(HISTORY.read_text())
        return [h for h in data if isinstance(h, dict)][-KEEP:]
    except (OSError, ValueError):
        return []


def summary(**extra) -> dict:
    h = history()
    avg = None
    if h:
        avg = {k: round(sum(x[k] for x in h) / len(h), 1) for k in ("down", "up", "ping")}
        avg["count"] = len(h)
    return {"ok": True, "last": h[-1] if h else None, "average": avg, **extra}


def speedtest() -> dict:
    try:
        ping = _ping()
    except OSError:
        return summary(ok=False, message="The speed test server could not be reached.")
    down = _run_threads(_download, 8.0)
    up = _run_threads(_upload, 6.0)
    if down <= 0:
        return summary(ok=False, message="The download test did not get any data.")
    result = {"time": int(time.time()), "down": round(down, 1), "up": round(up, 1), "ping": round(ping, 1),
              "via": default_device()}
    h = history() + [result]
    HISTORY.parent.mkdir(parents=True, exist_ok=True)
    HISTORY.write_text(json.dumps(h[-KEEP:]))
    return summary(message="Speed test done.")


# ---- commands ----------------------------------------------------------------------
def main() -> None:
    a = sys.argv[1:]
    password = None
    if "--password-stdin" in a:                      # Settings sends the Wi-Fi password here
        a = [x for x in a if x != "--password-stdin"]
        password = sys.stdin.readline().rstrip("\n")
    if a == ["state"]:
        state()
    elif a == ["scan"]:
        nmcli("device", "wifi", "rescan")
        time.sleep(1.2)            # give the driver a moment to report
        state()
    elif len(a) == 2 and a[0] == "radio" and a[1] in ("on", "off"):
        nmcli("radio", "wifi", a[1])
        time.sleep(0.5 if a[1] == "off" else 2.0)
        state()
    elif len(a) in (2, 3) and a[0] == "join":
        res = join(a[1], a[2] if len(a) == 3 else password)
        wrong = res.returncode != 0 and "Secrets were required" in res.stderr
        state(joined=res.returncode == 0,
              message=f"Connected to {a[1]}." if res.returncode == 0
              else "Wrong password, or the network did not take it." if wrong
              else error_of(res, "Could not connect."))
    elif len(a) == 2 and a[0] == "up":
        res = nmcli("connection", "up", a[1], timeout=60)
        state(joined=res.returncode == 0,
              message="Connected." if res.returncode == 0 else error_of(res, "Could not connect."))
    elif len(a) == 2 and a[0] in ("down", "leave"):
        res = nmcli("connection", "down", a[1]) if a[0] == "down" else nmcli("connection", "down", "id", a[1])
        state(message="Disconnected." if res.returncode == 0 else error_of(res, "Could not disconnect."))
    elif len(a) == 3 and a[0] == "wired" and a[2] in ("up", "down"):
        res = nmcli("device", "connect" if a[2] == "up" else "disconnect", a[1], timeout=60)
        ok = res.returncode == 0
        state(message=("Cable connected." if a[2] == "up" else "Cable disconnected.") if ok
              else error_of(res, "NetworkManager said no."))
    elif len(a) == 2 and a[0] == "details":
        d = details(a[1])
        print(json.dumps({"ok": d is not None, "details": d, "message": "" if d else "That connection is gone."}))
    elif len(a) == 3 and a[0] == "apply":
        try:
            wanted = json.loads(a[2])
        except ValueError:
            wanted = None
        if not isinstance(wanted, dict):
            print(json.dumps({"ok": False, "message": "Bad settings."}))
            raise SystemExit(1)
        ok, message = apply(a[1], wanted)
        print(json.dumps({"ok": ok, "details": details(a[1]), "message": message}))
    elif len(a) == 2 and a[0] == "forget":
        res = nmcli("connection", "delete", a[1])
        state(message="Forgotten." if res.returncode == 0 else error_of(res, "Could not forget it."))
    elif a == ["speedtest"]:
        print(json.dumps(speedtest()))
    elif a == ["speed"]:
        print(json.dumps(summary()))
    else:
        print(json.dumps({"ok": False, "message": "usage: state | scan | radio on|off | join <ssid> [--password-stdin] | "
                                                  "up <uuid> | down <uuid> | wired <device> up|down | details <uuid> | "
                                                  "apply <uuid> <json> | forget <uuid> | speedtest | speed"}))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
