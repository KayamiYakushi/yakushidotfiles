#!/usr/bin/env python3
"""Match the terminal and the shell to the Yakushi accent colour.

Commands:
    status      Detected terminals / shell and whether matching is on (JSON).
    enable      Turn matching on and apply the current accent.
    disable     Turn matching off and undo every change.
    sync        Re-apply after the accent changed (no-op while off).
    opacity <0.30..1.00>
                Terminal background opacity (kitty, alacritty, foot,
                ghostty). Until set here, your own opacity setting stays.
    blur on|off Blur behind terminal windows (done by Hyprland, so it works
                for every terminal). Turning it on below ~97% opacity
                lowers the opacity to 85% so the blur can be seen.
    blur-strength <1..10>
                Blur radius (Hyprland's blur size/passes; this also affects
                other blurred surfaces such as the launcher).

What it touches (only for programs that are installed):
    kitty     ~/.config/kitty/yakushi-theme.conf + one `include` line in
              kitty.conf; running kitty windows reload instantly (SIGUSR1).
    alacritty ~/.config/alacritty/yakushi-theme.toml + an `import` entry;
              alacritty reloads it by itself.
    foot      ~/.config/foot/yakushi-theme.ini + an `include=` line
              (new windows).
    ghostty   ~/.config/ghostty/yakushi-theme + a `config-file =` line
              (new windows).
    Hyprland  ~/.config/hypr/terminal.local.lua (blur strength, a no-blur
              rule for terminals when blur is off, and an opacity rule when
              your default terminal has no colour support here, e.g.
              wezterm/konsole) + one `dofile` line in hyprland.lua.
    fish      ~/.config/fish/conf.d/yakushi-colors.fish applies the colours as
              global variables (they win over fish's default theme and a
              theme set in config.fish), fed from one universal variable so
              open fish sessions follow later accent changes instantly. Your
              own fish colour settings are never modified.

Every line it adds to a config file contains "yakushi-theme" (the include
names the theme file), so `disable` can find and remove exactly those lines. Runs only when called: no daemon, no timers.
"""
from __future__ import annotations

import colorsys
import json
import os
import pwd
import re
import shutil
import signal
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
CONFIG = HOME / ".config"
STATE = CONFIG / "quickshell/yakushi-term.local.json"
UI_STATE = CONFIG / "quickshell/yakushi-ui.local.json"
HYPR_CONF = CONFIG / "hypr/hyprland.lua"

HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
MARK = "yakushi-theme"

FISH_VARS = (
    "fish_color_command", "fish_color_keyword", "fish_color_param",
    "fish_color_quote", "fish_color_redirection", "fish_color_end",
    "fish_color_error", "fish_color_comment", "fish_color_autosuggestion",
    "fish_color_operator", "fish_color_escape", "fish_color_valid_path",
    "fish_color_selection", "fish_color_search_match", "fish_color_cancel",
    "fish_pager_color_prefix", "fish_pager_color_completion",
    "fish_pager_color_description", "fish_pager_color_progress",
    "fish_pager_color_selected_background",
)


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

def load_state() -> dict:
    try:
        data = json.loads(STATE.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2) + "\n")


def accent() -> str:
    try:
        value = json.loads(UI_STATE.read_text()).get("accent")
        if isinstance(value, str) and HEX.match(value):
            return value.lower()
    except (OSError, ValueError, AttributeError):
        pass
    return "#ffffff"


# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

TERMINALS = ("kitty", "alacritty", "foot", "ghostty")   # colour support

# Hyprland window classes of common terminals (for blur / opacity rules).
TERMINAL_CLASSES = {
    "kitty": ["kitty"],
    "alacritty": ["Alacritty", "alacritty"],
    "foot": ["foot", "footclient"],
    "footclient": ["foot", "footclient"],
    "ghostty": ["com.mitchellh.ghostty", "ghostty"],
    "wezterm": ["org.wezfurlong.wezterm", "wezterm"],
    "konsole": ["org.kde.konsole", "konsole"],
    "gnome-terminal": ["org.gnome.Terminal", "gnome-terminal-server"],
    "kgx": ["org.gnome.Console"],
    "ptyxis": ["org.gnome.Ptyxis"],
    "xfce4-terminal": ["xfce4-terminal", "Xfce4-terminal"],
    "tilix": ["com.gexperts.Tilix"],
    "terminator": ["terminator", "Terminator"],
    "st": ["st-256color", "st"],
    "urxvt": ["URxvt", "urxvt"],
    "xterm": ["XTerm", "xterm"],
    "rio": ["rio"],
    "contour": ["contour"],
    "warp-terminal": ["dev.warp.Warp"],
}

WRAPPERS = {"uwsm", "app", "uwsm-app", "--", "env", "exec", "setsid", "runapp", "app2unit"}


def installed(name: str) -> bool:
    return shutil.which(name) is not None


def _first_program(command: str) -> str:
    """`uwsm app -- kitty -1` -> kitty;  `env FOO=1 foot` -> foot."""
    for token in command.split():
        if token in WRAPPERS or token.startswith("-") or "=" in token:
            continue
        return Path(token).name
    return ""


def _xdg_terminal() -> str:
    for path in (CONFIG / "hypr/xdg-terminals.list", CONFIG / "xdg-terminals.list"):
        try:
            for line in path.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    name = line.removesuffix(".desktop").split(".")[-1].lower()
                    return "gnome-terminal" if name == "terminal" else name
        except OSError:
            continue
    return ""


def preferred_terminal() -> str:
    """The terminal Hyprland opens (SUPER + Q), else $TERMINAL, else the
    xdg-terminal-exec choice, else the first supported one installed."""
    name = ""
    try:
        match = re.search(r'^\s*(?:local\s+)?terminal\s*=\s*["\']([^"\']+)["\']',
                          HYPR_CONF.read_text(), re.M)
        if match:
            name = _first_program(match.group(1))
    except OSError:
        pass
    if not name or name == "xdg-terminal-exec":
        name = _first_program(os.environ.get("TERMINAL", "")) or _xdg_terminal() or name
    if not name:
        name = next((t for t in TERMINALS if installed(t)), "")
    return name


def login_shell() -> str:
    try:
        return Path(pwd.getpwuid(os.getuid()).pw_shell).name
    except (KeyError, OSError):
        return Path(os.environ.get("SHELL", "")).name


# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

def rgb(hex_colour: str) -> tuple[float, float, float]:
    h = hex_colour.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))  # type: ignore


def to_hex(r: float, g: float, b: float) -> str:
    return "#" + "".join(f"{round(max(0, min(1, c)) * 255):02x}" for c in (r, g, b))


def mix(a: str, b: str, t: float) -> str:
    ra, rb = rgb(a), rgb(b)
    return to_hex(*(x + (y - x) * t for x, y in zip(ra, rb)))


def lighten(colour: str, amount: float) -> str:
    h, l, s = colorsys.rgb_to_hls(*rgb(colour))
    return to_hex(*colorsys.hls_to_rgb(h, min(1, l + amount), s))


OPACITY_MIN = 0.30


def palette(acc: str) -> dict:
    # Near-black with a visible hint of the accent, so the terminal itself
    # changes colour with the theme (not just the cursor).
    bg = mix("#0b0b0b", acc, 0.10)
    fg = "#e4e4e4"
    # Muted, readable ANSI colours that sit well on near-black; magenta is
    # the accent slot, so prompts and tools that use it follow the theme.
    return {
        "bg": bg,
        "fg": fg,
        "accent": acc,
        "cursor": acc,
        "selection": mix(bg, acc, 0.38),
        "ansi": [
            "#1c1c1c", "#ff5f6d", "#9ece6a", "#e6c07b",
            "#7aa2f7", acc, "#7dcfff", "#c8c8c8",
            "#4a4a4a", "#ff7b86", "#b5e48c", "#f2d49b",
            "#9ab8ff", lighten(acc, 0.12), "#a4e0ff", "#ffffff",
        ],
    }


# ---------------------------------------------------------------------------
# Config file helpers
# ---------------------------------------------------------------------------

def strip_marked(text: str) -> str:
    return "".join(line for line in text.splitlines(keepends=True) if MARK not in line)


def ensure_line(path: Path, line: str, at_top: bool = False) -> None:
    """Add a marked line once; create the file if needed."""
    path.parent.mkdir(parents=True, exist_ok=True)
    text = path.read_text() if path.exists() else ""
    if MARK in text:
        return
    if path.exists():
        backup = path.with_name(path.name + ".yakushi-before")
        if not backup.exists():
            shutil.copy2(path, backup)
    if at_top:
        text = line + "\n" + text
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        text += line + "\n"
    path.write_text(text)


def remove_lines(path: Path) -> None:
    if path.exists():
        text = path.read_text()
        cleaned = strip_marked(text)
        if cleaned.strip() == "":
            path.unlink()          # we created it; nothing of the user's in it
        elif cleaned != text:
            path.write_text(cleaned)


# ---------------------------------------------------------------------------
# Terminals
# ---------------------------------------------------------------------------

def apply_kitty(p: dict) -> str:
    d = CONFIG / "kitty"
    a = p["ansi"]
    lines = [
        f"# {MARK}: written by Yakushi Settings -> Appearance -> Terminal",
        f"foreground {p['fg']}",
        f"background {p['bg']}",
        f"cursor {p['cursor']}",
        f"cursor_text_color {p['bg']}",
        f"selection_foreground {p['fg']}",
        f"selection_background {p['selection']}",
        f"url_color {p['accent']}",
        f"active_border_color {p['accent']}",
        f"inactive_border_color {mix(p['bg'], p['fg'], 0.18)}",
        f"active_tab_foreground {p['bg']}",
        f"active_tab_background {p['accent']}",
        f"inactive_tab_foreground {mix(p['bg'], p['fg'], 0.6)}",
        f"inactive_tab_background {p['bg']}",
        f"mark1_background {p['accent']}",
    ] + [f"color{i} {c}" for i, c in enumerate(a)]
    if p.get("opacity") is not None:
        lines += [
            "dynamic_background_opacity yes",
            f"background_opacity {p['opacity']:.2f}",
        ]
    d.mkdir(parents=True, exist_ok=True)
    (d / "yakushi-theme.conf").write_text("\n".join(lines) + "\n")
    # Last include wins, so ours goes at the end of kitty.conf.
    ensure_line(d / "kitty.conf", "include yakushi-theme.conf")
    reload_kitty()
    if p.get("opacity") is not None:
        set_kitty_opacity(p["opacity"])
    return "kitty"


def set_kitty_opacity(value: float) -> None:
    """Live change for open windows (needs kitty remote control); the config
    value above covers new windows either way."""
    if shutil.which("kitten") is None:
        return
    for sock in Path("/tmp").glob("kitty-*") if Path("/tmp").exists() else []:
        try:
            subprocess.run(["kitten", "@", "--to", f"unix:{sock}", "set-background-opacity",
                            "--all", f"{value:.2f}"], capture_output=True, timeout=3)
        except (OSError, subprocess.TimeoutExpired):
            pass


def reload_kitty() -> None:
    try:
        pids = subprocess.run(["pgrep", "-x", "kitty"], capture_output=True, text=True).stdout.split()
    except OSError:
        return
    for pid in pids:
        try:
            os.kill(int(pid), signal.SIGUSR1)
        except (ValueError, ProcessLookupError, PermissionError):
            pass


def apply_alacritty(p: dict) -> str:
    d = CONFIG / "alacritty"
    a = p["ansi"]
    names = ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")
    lines = [
        f"# {MARK}: written by Yakushi Settings -> Appearance -> Terminal",
        "[colors.primary]",
        f'background = "{p["bg"]}"',
        f'foreground = "{p["fg"]}"',
        "[colors.cursor]",
        f'cursor = "{p["cursor"]}"',
        f'text = "{p["bg"]}"',
        "[colors.selection]",
        f'background = "{p["selection"]}"',
        f'text = "{p["fg"]}"',
        "[colors.normal]",
    ] + [f'{n} = "{a[i]}"' for i, n in enumerate(names)] + ["[colors.bright]"] + [
        f'{n} = "{a[i + 8]}"' for i, n in enumerate(names)
    ]
    if p.get("opacity") is not None:
        lines += ["[window]", f"opacity = {p['opacity']:.2f}"]
    d.mkdir(parents=True, exist_ok=True)
    theme = d / "yakushi-theme.toml"
    theme.write_text("\n".join(lines) + "\n")

    conf = d / "alacritty.toml"
    entry = f'import = ["{theme}"]  # {MARK}'
    text = conf.read_text() if conf.exists() else ""
    if MARK in text:
        return "alacritty"
    if re.search(r"^\s*import\s*=", text, re.M):
        return "alacritty (add yakushi-theme.toml to your existing import list)"
    if re.search(r"^\s*\[general\]\s*$", text, re.M):
        if conf.exists():
            shutil.copy2(conf, conf.with_name(conf.name + ".yakushi-before"))
        text = re.sub(r"^(\s*\[general\]\s*)$", r"\1\n" + entry.replace("\\", "\\\\"), text, count=1, flags=re.M)
        conf.write_text(text)
    else:
        ensure_line(conf, f"[general]  # {MARK}\n{entry}", at_top=True)
    return "alacritty"


def apply_foot(p: dict) -> str:
    d = CONFIG / "foot"
    a = [c.lstrip("#") for c in p["ansi"]]
    lines = [
        f"# {MARK}: written by Yakushi Settings -> Appearance -> Terminal",
        "[cursor]",
        f"color={p['bg'].lstrip('#')} {p['cursor'].lstrip('#')}",
        "[colors]",
        f"foreground={p['fg'].lstrip('#')}",
        f"background={p['bg'].lstrip('#')}",
        f"selection-foreground={p['fg'].lstrip('#')}",
        f"selection-background={p['selection'].lstrip('#')}",
    ] + [f"regular{i}={a[i]}" for i in range(8)] + [f"bright{i}={a[i + 8]}" for i in range(8)]
    if p.get("opacity") is not None:
        lines.append(f"alpha={p['opacity']:.2f}")
    d.mkdir(parents=True, exist_ok=True)
    theme = d / "yakushi-theme.ini"
    theme.write_text("\n".join(lines) + "\n")
    # include= belongs to the main section, i.e. before any [section].
    ensure_line(d / "foot.ini", f"include={theme}", at_top=True)
    return "foot"


def apply_ghostty(p: dict) -> str:
    d = CONFIG / "ghostty"
    lines = [
        f"# {MARK}: written by Yakushi Settings -> Appearance -> Terminal",
        f"background = {p['bg']}",
        f"foreground = {p['fg']}",
        f"cursor-color = {p['cursor']}",
        f"selection-background = {p['selection']}",
        f"selection-foreground = {p['fg']}",
    ] + [f"palette = {i}={c}" for i, c in enumerate(p["ansi"])]
    if p.get("opacity") is not None:
        lines.append(f"background-opacity = {p['opacity']:.2f}")
    d.mkdir(parents=True, exist_ok=True)
    (d / "yakushi-theme").write_text("\n".join(lines) + "\n")
    ensure_line(d / "config", "config-file = yakushi-theme")
    return "ghostty"


def remove_terminals() -> None:
    for path in (
        CONFIG / "kitty/kitty.conf", CONFIG / "foot/foot.ini", CONFIG / "ghostty/config",
        CONFIG / "alacritty/alacritty.toml",
    ):
        remove_lines(path)
    for path in (
        CONFIG / "kitty/yakushi-theme.conf", CONFIG / "alacritty/yakushi-theme.toml",
        CONFIG / "foot/yakushi-theme.ini", CONFIG / "ghostty/yakushi-theme",
    ):
        try:
            path.unlink()
        except OSError:
            pass
    reload_kitty()


# ---------------------------------------------------------------------------
# Hyprland: blur + opacity fallback (works for any terminal)
# ---------------------------------------------------------------------------

HYPR_LOCAL = CONFIG / "hypr/terminal.local.lua"
HYPR_INCLUDE = 'pcall(dofile, os.getenv("HOME") .. "/.config/hypr/terminal.local.lua")'
BLUR_DEFAULT_STRENGTH = 3     # = Hyprland's size 5, passes 1 (hyprland.lua default)


def blur_params(strength: int) -> tuple[int, int]:
    strength = max(1, min(10, strength))
    size = strength + 2
    passes = 1 if strength <= 3 else 2 if strength <= 7 else 3
    return size, passes


def terminal_classes(names) -> list[str]:
    classes = []
    for name in names:
        for cls in TERMINAL_CLASSES.get(name, [name]):
            if cls and cls not in classes:
                classes.append(cls)
    return classes


def class_regex(classes: list[str]) -> str:
    escaped = [re.sub(r"([.+*?()\[\]{}|^$\\])", r"\\\1", c) for c in classes]
    return "^(" + "|".join(escaped) + ")$"


def lua_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def hypr_lua(state: dict) -> tuple[str, str]:
    """(config part, rules part) of terminal.local.lua."""
    blur = state.get("blur", True) is not False
    size, passes = blur_params(int(state.get("blur_strength", BLUR_DEFAULT_STRENGTH)))
    config = (
        "hl.config({ decoration = { blur = { "
        + ("enabled = true, " if blur else "")
        + f"size = {size}, passes = {passes} }} }} }})\n"
    )
    rules = ""
    term = preferred_terminal()
    if not blur:
        names = list(TERMINAL_CLASSES) + ([term] if term else [])
        rules += (
            "hl.window_rule({\n"
            '    name = "yakushi-terminal-no-blur",\n'
            f"    match = {{ class = {lua_string(class_regex(terminal_classes(names)))} }},\n"
            "    no_blur = true,\n"
            "})\n"
        )
    opacity = state.get("opacity")
    if term and term not in TERMINALS and term != "footclient" and isinstance(opacity, (int, float)) \
            and opacity < 0.995:
        # No colour/opacity support for this terminal: Hyprland makes the
        # whole window translucent instead.
        rules += (
            "hl.window_rule({\n"
            '    name = "yakushi-terminal-opacity",\n'
            f"    match = {{ class = {lua_string(class_regex(terminal_classes([term])))} }},\n"
            f'    opacity = "{max(OPACITY_MIN, min(1.0, float(opacity))):.2f} override",\n'
            "})\n"
        )
    return config, rules


def ensure_hypr_include() -> None:
    try:
        text = HYPR_CONF.read_text()
    except OSError:
        return
    if "terminal.local.lua" in text:
        return
    line = ("-- Terminal blur/opacity from Settings -> Appearance -> Terminal (machine-local)\n"
            + HYPR_INCLUDE + "\n")
    match = re.search(r'^require\(\s*["\']rules["\']\s*\)[^\n]*\n', text, re.M)
    if match:
        text = text[:match.end()] + line + text[match.end():]
    else:
        text = text.rstrip("\n") + "\n\n" + line
    HYPR_CONF.write_text(text)


def hyprctl(*args: str) -> bool:
    try:
        proc = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return False      # not in a Hyprland session: applies at next login
    out = (proc.stdout + proc.stderr).lower()
    return proc.returncode == 0 and "error" not in out and "unknown" not in out


def apply_hypr(state: dict) -> None:
    config, rules = hypr_lua(state)
    header = (f"-- {MARK}: terminal blur/opacity, written by Settings -> Appearance ->\n"
              "-- Terminal (yakushi-termctl.py). Machine-local; safe to delete.\n")
    new = header + config + rules
    old = HYPR_LOCAL.read_text() if HYPR_LOCAL.exists() else None
    if new == old:
        return
    HYPR_LOCAL.parent.mkdir(parents=True, exist_ok=True)
    HYPR_LOCAL.write_text(new)
    ensure_hypr_include()
    old_rules = old.split(")\n", 1)[1] if old and ")\n" in old else None
    if old is None or old_rules != rules:
        hyprctl("reload")       # window rules need a config reload
        return
    # Only the blur strength changed: apply live, no reload.
    if not hyprctl("eval", config):
        blur = state.get("blur", True) is not False
        size, passes = blur_params(int(state.get("blur_strength", BLUR_DEFAULT_STRENGTH)))
        hyprctl("keyword", "decoration:blur:size", str(size))
        hyprctl("keyword", "decoration:blur:passes", str(passes))
        if blur:
            hyprctl("keyword", "decoration:blur:enabled", "true")


def remove_hypr() -> None:
    if HYPR_LOCAL.exists():
        HYPR_LOCAL.unlink()
        hyprctl("reload")


# ---------------------------------------------------------------------------
# fish
# ---------------------------------------------------------------------------

FISH_CONF = CONFIG / "fish/conf.d/yakushi-colors.fish"

FISH_SNIPPET = """# yakushi-theme: written by Yakushi Settings -> Appearance -> Terminal.
# Applies the theme colours as *global* variables: they win over fish's
# default theme, and they follow the universal list `yakushi_colors`, so every
# open fish updates the moment Settings changes the accent. Turning matching
# off in Settings removes this file and the list; your own colour settings
# are never touched.

function __yakushi_apply_colors --on-variable yakushi_colors
    if set -q yakushi_colors[1]
        for pair in $yakushi_colors
            set -l kv (string split -m 1 = -- $pair)
            set -g $kv[1] (string split ' ' -- $kv[2])
        end
    else if set -q __yakushi_color_names[1]
        for name in $__yakushi_color_names
            set -e -g $name
        end
    end
    set -g __yakushi_color_names (string replace -r '=.*' '' -- $yakushi_colors)
end

__yakushi_apply_colors

# Once more after config.fish, in case it sets colours of its own.
function __yakushi_after_config --on-event fish_prompt
    functions -e __yakushi_after_config
    __yakushi_apply_colors
end
"""


def fish(script: str) -> str:
    try:
        # Not --no-config: that also skips universal variables.
        return subprocess.run(["fish", "-c", script], capture_output=True,
                              text=True, timeout=10, stdin=subprocess.DEVNULL).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def fish_quote(text: str) -> str:
    return "'" + text.replace("\\", "\\\\").replace("'", "\\'") + "'"


def fish_values(p: dict) -> dict:
    acc = p["accent"].lstrip("#")
    sel = p["selection"].lstrip("#")
    return {
        "fish_color_command": f"{acc}",
        "fish_color_keyword": f"{acc} --bold",
        "fish_color_param": "e4e4e4",
        "fish_color_quote": "9ece6a",
        "fish_color_redirection": "7dcfff",
        "fish_color_end": f"{acc}",
        "fish_color_error": "ff5f6d",
        "fish_color_comment": "6b6b6b --italics",
        "fish_color_autosuggestion": "5a5a5a",
        "fish_color_operator": "7dcfff",
        "fish_color_escape": "e6c07b",
        "fish_color_valid_path": "--underline",
        "fish_color_selection": f"e4e4e4 --background={sel}",
        "fish_color_search_match": f"--background={sel}",
        "fish_color_cancel": "ff5f6d",
        "fish_pager_color_prefix": f"{acc} --bold",
        "fish_pager_color_completion": "e4e4e4",
        "fish_pager_color_description": "8a8a8a",
        "fish_pager_color_progress": f"{acc}",
        "fish_pager_color_selected_background": f"--background={sel}",
    }


def undo_old_fish(state: dict) -> None:
    """Earlier versions wrote universal fish_color_* directly; put them back."""
    backup = state.pop("fishBackup", None)
    if backup is None:
        return
    cmds = []
    for name in FISH_VARS:
        if backup.get(name):
            cmds.append(f"set -U {name} {backup[name]}")
        else:
            cmds.append(f"set -eU {name}")
    fish("; ".join(cmds))


def apply_fish(p: dict, state: dict) -> str:
    undo_old_fish(state)
    FISH_CONF.parent.mkdir(parents=True, exist_ok=True)
    FISH_CONF.write_text(FISH_SNIPPET)
    pairs = " ".join(fish_quote(f"{k}={v}") for k, v in fish_values(p).items())
    fish(f"set -U yakushi_colors {pairs}")
    return "fish"


def restore_fish(state: dict) -> None:
    undo_old_fish(state)
    fish("set -eU yakushi_colors")
    try:
        FISH_CONF.unlink()
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

APPLIERS = {
    "kitty": apply_kitty,
    "alacritty": apply_alacritty,
    "foot": apply_foot,
    "ghostty": apply_ghostty,
}


def detected() -> dict:
    term = preferred_terminal()
    return {
        "terminal": term,
        "terminalColours": term in TERMINALS or term == "footclient",
        "terminals": [t for t in TERMINALS if installed(t)],
        "shell": login_shell(),
        "fish": installed("fish"),
    }


def settings(state: dict) -> dict:
    return {
        "enabled": state.get("enabled") is True,
        "opacity": state.get("opacity", 1.0),
        "opacitySet": isinstance(state.get("opacity"), (int, float)),
        "blur": state.get("blur", True) is not False,
        "blurStrength": int(state.get("blur_strength", BLUR_DEFAULT_STRENGTH)),
    }


def apply_all(state: dict) -> list[str]:
    p = palette(accent())
    if isinstance(state.get("opacity"), (int, float)):
        p["opacity"] = max(OPACITY_MIN, min(1.0, float(state["opacity"])))
    done = []
    for name, apply in APPLIERS.items():
        if installed(name):
            try:
                done.append(apply(p))
            except OSError as exc:
                done.append(f"{name} (failed: {exc})")
    if installed("fish"):
        done.append(apply_fish(p, state))
    apply_hypr(state)
    return done


def main() -> None:
    args = sys.argv[1:]
    state = load_state()

    if args == ["status"]:
        emit({"ok": True, **settings(state), **detected()})

    elif len(args) == 2 and args[0] == "opacity":
        try:
            value = max(OPACITY_MIN, min(1.0, float(args[1])))
        except ValueError:
            emit({"ok": False, "message": "Invalid opacity."})
            raise SystemExit(1)
        state["opacity"] = round(value, 2)
        if state.get("enabled") is True:
            apply_all(state)
        save_state(state)
        emit({"ok": True, **settings(state),
              "message": f"Terminal opacity {round(value * 100)}%."})

    elif len(args) == 2 and args[0] == "blur" and args[1] in ("on", "off"):
        state["blur"] = args[1] == "on"
        note = ""
        if state["blur"]:
            current = state.get("opacity")
            if not isinstance(current, (int, float)) or current >= 0.97:
                state["opacity"] = 0.85
                note = " Opacity set to 85% so the blur shows."
        if state.get("enabled") is True:
            apply_all(state)
        save_state(state)
        emit({"ok": True, **settings(state),
              "message": ("Terminal blur on." + note) if state["blur"] else "Terminal blur off."})

    elif len(args) == 2 and args[0] == "blur-strength":
        try:
            value = max(1, min(10, int(round(float(args[1])))))
        except ValueError:
            emit({"ok": False, "message": "Invalid blur strength."})
            raise SystemExit(1)
        state["blur_strength"] = value
        if state.get("enabled") is True:
            apply_hypr(state)
        save_state(state)
        emit({"ok": True, **settings(state), "message": f"Blur strength {value}."})

    elif args == ["enable"]:
        state["enabled"] = True
        done = apply_all(state)
        save_state(state)
        message = ("Colours applied to " + ", ".join(done) + ".") if done else \
            "No supported terminal (kitty, alacritty, foot, ghostty) or fish found."
        info = detected()
        if info["terminal"] and not info["terminalColours"]:
            message += f" {info['terminal']}: blur and opacity only (via Hyprland)."
        emit({"ok": True, **settings(state), "applied": done, "message": message, **info})

    elif args == ["disable"]:
        remove_terminals()
        restore_fish(state)
        remove_hypr()
        state["enabled"] = False
        save_state(state)
        emit({"ok": True, **settings(state), "message": "Terminal colours restored.", **detected()})

    elif args == ["sync"]:
        if state.get("enabled") is True:
            apply_all(state)
            save_state(state)
        emit({"ok": True})

    else:
        emit({"ok": False, "message": "Usage: status | enable | disable | sync | opacity <0.3-1> | blur on|off | blur-strength <1-10>"})
        raise SystemExit(1)


if __name__ == "__main__":
    main()
