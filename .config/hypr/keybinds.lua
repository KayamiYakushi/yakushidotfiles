-- ~/.config/hypr/keybinds.lua
-- Yakushi-managed keybinds
-- Docs: https://wiki.hypr.land/Configuring/Basics/Binds/
--       https://wiki.hypr.land/Configuring/Basics/Dispatchers/
--
-- Lines tagged with YAKUSHI_BIND are managed by Yakushi Settings.
-- The dispatcher/action code remains native Hyprland Lua.

local home = os.getenv("HOME")
local menu = "rofi -show drun"

-- Yakushi persistent enable/disable layer
local yakushiDisabled = {}
do
    local f = io.open(home .. "/.config/hypr/yakushi-disabled-binds.txt", "r")
    if f ~= nil then
        for line in f:lines() do
            if line ~= "" then yakushiDisabled[line] = true end
        end
        f:close()
    end
end

local function yakushi_bind(id, ...)
    if yakushiDisabled[id] then return end
    return hl.bind(...)
end


-- Launchers
-- YAKUSHI_BIND terminal|Launchers|Terminal
yakushi_bind("terminal", "SUPER + Q", hl.dsp.exec_cmd(terminal))
-- YAKUSHI_BIND launcher|Launchers|Applications
yakushi_bind("launcher", "SUPER + Space", hl.dsp.exec_cmd("pgrep -x rofi >/dev/null && pkill -x rofi || " .. menu))
-- YAKUSHI_BIND files|Launchers|File Manager
yakushi_bind("files", "SUPER + E", hl.dsp.exec_cmd(fileManager))
-- YAKUSHI_BIND browser|Launchers|Browser
yakushi_bind("browser", "SUPER + B", hl.dsp.exec_cmd(browser))
-- YAKUSHI_BIND settings|Launchers|Yakushi Settings
yakushi_bind("settings", "SUPER + I", hl.dsp.exec_cmd("~/.config/quickshell/scripts/toggle-settings.sh"))
-- YAKUSHI_BIND wallpaper|Launchers|Wallpaper Selector
yakushi_bind("wallpaper", "SUPER + W", hl.dsp.exec_cmd("~/.config/quickshell/hyprquickpaper/launch.sh"))

-- Session / window basics
-- YAKUSHI_BIND close|Windows|Close Window
yakushi_bind("close", "SUPER + C", hl.dsp.window.close())
-- YAKUSHI_BIND lock|System|Lock Screen
yakushi_bind("lock", "SUPER + Tab", hl.dsp.exec_cmd("hyprlock"))
-- YAKUSHI_BIND power|System|Power Menu
yakushi_bind("power", "SUPER + GRAVE", hl.dsp.exec_cmd("$HOME/.config/rofi/scripts/yakushi-power-menu.sh"))
-- YAKUSHI_BIND fullscreen|Windows|Fullscreen
yakushi_bind("fullscreen", "SUPER + F", hl.dsp.window.fullscreen({ mode = 0 }))
-- YAKUSHI_BIND opacity|Windows|Window Opacity
yakushi_bind("opacity", "SUPER + O", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/opacity.sh"))

-- Mouse move/resize window
-- YAKUSHI_BIND mouse_move|Windows|Move Window With Mouse
yakushi_bind("mouse_move", "SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
-- YAKUSHI_BIND mouse_resize|Windows|Resize Window With Mouse
yakushi_bind("mouse_resize", "SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Waybar / clipboard
-- YAKUSHI_BIND waybar|System|Toggle Waybar
yakushi_bind("waybar", "SUPER + SHIFT + W", hl.dsp.exec_cmd("sh -c 'pgrep -x waybar >/dev/null && pkill waybar || nohup waybar >/dev/null 2>&1 &'"))
-- YAKUSHI_BIND clipboard|Utilities|Clipboard History
yakushi_bind("clipboard", "SUPER + V", hl.dsp.exec_cmd("pgrep -x rofi >/dev/null && pkill -x rofi || cliphist list | rofi -dmenu -p '' | cliphist decode | wl-copy"))

-- Screenshots
-- YAKUSHI_BIND screenshot_full|Screenshots|Full Screenshot
yakushi_bind("screenshot_full", "SUPER + Delete", hl.dsp.exec_cmd("grim " .. home .. "/Pictures/$(date +%s).png"))
-- YAKUSHI_BIND screenshot_area|Screenshots|Area Screenshot + Clipboard
yakushi_bind("screenshot_area", "SUPER + SHIFT + S", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | tee "$HOME/Pictures/$(date +%s).png" | wl-copy]]))

-- Keyboard layout
-- YAKUSHI_BIND keyboard_layout|Input|Switch Keyboard Layout
yakushi_bind("keyboard_layout", "SUPER + X", hl.dsp.exec_cmd("hyprctl switchxkblayout current next"))

-- Toggle float window, center and resize
-- YAKUSHI_BIND float|Windows|Toggle Floating
yakushi_bind("float", "SUPER + SHIFT + V", function()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))

    local w = hl.get_active_window()
    if w ~= nil and w.floating then
        local mon = hl.get_active_monitor()
        if mon ~= nil then
            local target_w = math.floor(mon.width * 0.7)
            local target_h = math.floor(mon.height * 0.7)

            hl.dispatch(hl.dsp.window.resize({ x = target_w, y = target_h, relative = false }))

            local mon_x = mon.x or 0
            local mon_y = mon.y or 0
            local target_x = mon_x + math.floor((mon.width - target_w) / 2)
            local target_y = mon_y + math.floor((mon.height - target_h) / 2)

            hl.dispatch(hl.dsp.window.move({ x = target_x, y = target_y, relative = false }))
        end
    end
end)

-- Zoom
local function zoomfunction(value)
    local zoomvalue = hl.get_config("cursor:zoom_factor")
    if (zoomvalue + value) > 1.5 then
        hl.config({ cursor = { zoom_factor = 1.5 } })
    elseif (zoomvalue + value) < 1.0 then
        hl.config({ cursor = { zoom_factor = 1.0 } })
    else
        hl.config({ cursor = { zoom_factor = zoomvalue + value } })
    end
end

-- YAKUSHI_BIND zoom_out_wheel|Input|Zoom Out (Wheel)
yakushi_bind("zoom_out_wheel", "SUPER + mouse_down", function() zoomfunction(-0.5) end, { repeating = true })
-- YAKUSHI_BIND zoom_in_wheel|Input|Zoom In (Wheel)
yakushi_bind("zoom_in_wheel", "SUPER + mouse_up", function() zoomfunction(0.5) end, { repeating = true })
-- YAKUSHI_BIND zoom_out_keypad|Input|Zoom Out (Keypad)
yakushi_bind("zoom_out_keypad", "SUPER + code:82", function() zoomfunction(-0.3) end, { repeating = true })
-- YAKUSHI_BIND zoom_in_keypad|Input|Zoom In (Keypad)
yakushi_bind("zoom_in_keypad", "SUPER + code:86", function() zoomfunction(0.3) end, { repeating = true })

-- Session
-- YAKUSHI_BIND exit|System|Exit Hyprland|danger
yakushi_bind("exit", "SUPER + SHIFT + E", hl.dsp.exit())

-- Focus
-- YAKUSHI_BIND focus_left|Focus|Focus Left
yakushi_bind("focus_left", "SUPER + H", hl.dsp.focus({ direction = "left" }))
-- YAKUSHI_BIND focus_down|Focus|Focus Down
yakushi_bind("focus_down", "SUPER + J", hl.dsp.focus({ direction = "down" }))
-- YAKUSHI_BIND focus_up|Focus|Focus Up
yakushi_bind("focus_up", "SUPER + K", hl.dsp.focus({ direction = "up" }))
-- YAKUSHI_BIND focus_right|Focus|Focus Right
yakushi_bind("focus_right", "SUPER + L", hl.dsp.focus({ direction = "right" }))

-- Move windows
-- YAKUSHI_BIND move_left|Windows|Move Window Left
yakushi_bind("move_left", "SUPER + SHIFT + H", hl.dsp.window.move({ direction = "left" }))
-- YAKUSHI_BIND move_down|Windows|Move Window Down
yakushi_bind("move_down", "SUPER + SHIFT + J", hl.dsp.window.move({ direction = "down" }))
-- YAKUSHI_BIND move_up|Windows|Move Window Up
yakushi_bind("move_up", "SUPER + SHIFT + K", hl.dsp.window.move({ direction = "up" }))
-- YAKUSHI_BIND move_right|Windows|Move Window Right
yakushi_bind("move_right", "SUPER + SHIFT + L", hl.dsp.window.move({ direction = "right" }))

-- Resize windows
-- YAKUSHI_BIND resize_left|Windows|Resize Narrower
yakushi_bind("resize_left", "SUPER + CTRL + H", hl.dsp.window.resize({ x = -40, y = 0 }), { repeating = true })
-- YAKUSHI_BIND resize_right|Windows|Resize Wider
yakushi_bind("resize_right", "SUPER + CTRL + L", hl.dsp.window.resize({ x = 40, y = 0 }), { repeating = true })
-- YAKUSHI_BIND resize_up|Windows|Resize Shorter
yakushi_bind("resize_up", "SUPER + CTRL + K", hl.dsp.window.resize({ x = 0, y = -40 }), { repeating = true })
-- YAKUSHI_BIND resize_down|Windows|Resize Taller
yakushi_bind("resize_down", "SUPER + CTRL + J", hl.dsp.window.resize({ x = 0, y = 40 }), { repeating = true })

-- Workspaces
-- YAKUSHI_BIND ws_1|Workspaces|Workspace 1
yakushi_bind("ws_1", "SUPER + 1", hl.dsp.focus({ workspace = 1 }))
-- YAKUSHI_BIND move_ws_1|Workspaces|Move Window to Workspace 1
yakushi_bind("move_ws_1", "SUPER + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
-- YAKUSHI_BIND ws_2|Workspaces|Workspace 2
yakushi_bind("ws_2", "SUPER + 2", hl.dsp.focus({ workspace = 2 }))
-- YAKUSHI_BIND move_ws_2|Workspaces|Move Window to Workspace 2
yakushi_bind("move_ws_2", "SUPER + SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
-- YAKUSHI_BIND ws_3|Workspaces|Workspace 3
yakushi_bind("ws_3", "SUPER + 3", hl.dsp.focus({ workspace = 3 }))
-- YAKUSHI_BIND move_ws_3|Workspaces|Move Window to Workspace 3
yakushi_bind("move_ws_3", "SUPER + SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))
-- YAKUSHI_BIND ws_4|Workspaces|Workspace 4
yakushi_bind("ws_4", "SUPER + 4", hl.dsp.focus({ workspace = 4 }))
-- YAKUSHI_BIND move_ws_4|Workspaces|Move Window to Workspace 4
yakushi_bind("move_ws_4", "SUPER + SHIFT + 4", hl.dsp.window.move({ workspace = 4 }))
-- YAKUSHI_BIND ws_5|Workspaces|Workspace 5
yakushi_bind("ws_5", "SUPER + 5", hl.dsp.focus({ workspace = 5 }))
-- YAKUSHI_BIND move_ws_5|Workspaces|Move Window to Workspace 5
yakushi_bind("move_ws_5", "SUPER + SHIFT + 5", hl.dsp.window.move({ workspace = 5 }))
-- YAKUSHI_BIND ws_6|Workspaces|Workspace 6
yakushi_bind("ws_6", "SUPER + 6", hl.dsp.focus({ workspace = 6 }))
-- YAKUSHI_BIND move_ws_6|Workspaces|Move Window to Workspace 6
yakushi_bind("move_ws_6", "SUPER + SHIFT + 6", hl.dsp.window.move({ workspace = 6 }))
-- YAKUSHI_BIND ws_7|Workspaces|Workspace 7
yakushi_bind("ws_7", "SUPER + 7", hl.dsp.focus({ workspace = 7 }))
-- YAKUSHI_BIND move_ws_7|Workspaces|Move Window to Workspace 7
yakushi_bind("move_ws_7", "SUPER + SHIFT + 7", hl.dsp.window.move({ workspace = 7 }))
-- YAKUSHI_BIND ws_8|Workspaces|Workspace 8
yakushi_bind("ws_8", "SUPER + 8", hl.dsp.focus({ workspace = 8 }))
-- YAKUSHI_BIND move_ws_8|Workspaces|Move Window to Workspace 8
yakushi_bind("move_ws_8", "SUPER + SHIFT + 8", hl.dsp.window.move({ workspace = 8 }))
-- YAKUSHI_BIND ws_9|Workspaces|Workspace 9
yakushi_bind("ws_9", "SUPER + 9", hl.dsp.focus({ workspace = 9 }))
-- YAKUSHI_BIND move_ws_9|Workspaces|Move Window to Workspace 9
yakushi_bind("move_ws_9", "SUPER + SHIFT + 9", hl.dsp.window.move({ workspace = 9 }))
-- YAKUSHI_BIND ws_10|Workspaces|Workspace 10
yakushi_bind("ws_10", "SUPER + 0", hl.dsp.focus({ workspace = 10 }))
-- YAKUSHI_BIND move_ws_10|Workspaces|Move Window to Workspace 10
yakushi_bind("move_ws_10", "SUPER + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

-- Media keys
-- YAKUSHI_BIND volume_up|Media|Volume Up
yakushi_bind("volume_up", "XF86AudioRaiseVolume", hl.dsp.exec_cmd("~/.config/quickshell/scripts/volume-osd.sh up"), { locked = true, repeating = true })
-- YAKUSHI_BIND volume_down|Media|Volume Down
yakushi_bind("volume_down", "XF86AudioLowerVolume", hl.dsp.exec_cmd("~/.config/quickshell/scripts/volume-osd.sh down"), { locked = true, repeating = true })
-- YAKUSHI_BIND volume_mute|Media|Mute
yakushi_bind("volume_mute", "XF86AudioMute", hl.dsp.exec_cmd("~/.config/quickshell/scripts/volume-osd.sh mute"), { locked = true })
-- YAKUSHI_BIND media_play|Media|Play / Pause
yakushi_bind("media_play", "XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
-- YAKUSHI_BIND media_next|Media|Next Track
yakushi_bind("media_next", "XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
-- YAKUSHI_BIND media_prev|Media|Previous Track
yakushi_bind("media_prev", "XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
