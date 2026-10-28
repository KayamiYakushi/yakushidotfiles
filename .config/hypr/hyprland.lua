-- Yakushi · Hyprland
--
-- Settings (SUPER + I) edits a few values in this file in place: the apps
-- below (Default Apps), kb_layout and sensitivity (Input), gaps_in,
-- gaps_out and rounding (Appearance). Keep each of them on its own line.

-- Apps opened by SUPER + Q / E / B and SUPER + Space ------------------------
terminal    = "kitty"
fileManager = "nautilus"
browser     = "firefox"
menu        = "rofi -show drun"

-- Started once, at login -----------------------------------------------------
local startup = {
    "playerctld daemon",
    "sh ~/.config/quickshell/scripts/yakushi-bar.sh start",      -- top bar (Settings -> Top Bar)
    "wl-paste --type text --watch cliphist store",
    "wl-paste --type image --watch cliphist store",
    "systemctl --user start hyprpolkitagent.service",
    "hyprsunset",
    "sleep 1.5 && python3 ~/.config/hypr/scripts/yakushi-nightlightctl.py restore",
    "awww-daemon",
}

hl.on("hyprland.start", function()
    for _, cmd in ipairs(startup) do
        hl.exec_cmd(cmd)
    end
end)

-- Environment ------------------------------------------------------------------
for name, value in pairs({
    XCURSOR_SIZE = "14",
    QT_QPA_PLATFORM = "wayland",
    MOZ_ENABLE_WAYLAND = "1",
}) do
    hl.env(name, value)
end

-- Everything else, in one table --------------------------------------------------
hl.config({
    input = {
        kb_layout = "us",            -- set by the installer; Settings -> Input
        sensitivity = -0.60,         -- Settings -> Input
        follow_mouse = 1,
        touchpad = {
            tap_to_click = true,
            natural_scroll = false,
        },
    },

    general = {
        layout = "dwindle",
        gaps_in = 3,                 -- Settings -> Appearance
        gaps_out = 3,                -- Settings -> Appearance
        border_size = 0,             -- a border is added by window.local.lua
        resize_on_border = true,
        allow_tearing = false,
    },

    decoration = {
        rounding = 8,                -- Settings -> Appearance
        active_opacity = 1.0,        -- SUPER + O
        inactive_opacity = 1.0,      -- SUPER + O
        fullscreen_opacity = 1.0,    -- fullscreen stays solid
        blur = { enabled = true, size = 5, passes = 1, vibrancy = 0.2 },
        shadow = { enabled = true, range = 8, render_power = 3 },
    },

    render = { expand_undersized_textures = false },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    master = { new_status = "master" },

    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
})

-- Motion: a quick ease-out for windows, plain fades elsewhere -------------------
hl.curve("easeOut", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })

for _, a in ipairs({
    { "windows",    5, "easeOut" },
    { "windowsOut", 5, "easeOut" },
    { "border",     5, "default" },
    { "fade",       4, "default" },
    { "workspaces", 7, "default", "slidefade" },
}) do
    hl.animation({ leaf = a[1], enabled = true, speed = a[2], bezier = a[3], style = a[4] })
end

-- Machine-local pieces written by Settings (missing files are fine) -------------
local hypr = os.getenv("HOME") .. "/.config/hypr/"

pcall(dofile, hypr .. "window.local.lua")        -- shadow and border (Appearance)

require("monitors")
require("keybinds")
require("rules")

pcall(dofile, hypr .. "terminal.local.lua")      -- terminal blur / opacity (Appearance -> Terminal)
