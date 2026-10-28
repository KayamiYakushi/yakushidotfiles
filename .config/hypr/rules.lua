-- Yakushi · window and layer rules

-- Blur behind the rofi launcher, but not its fully transparent edges.
hl.layer_rule({ match = { namespace = "rofi" }, blur = true, ignore_alpha = 0.15 })

-- Window opacity lives in hyprland.lua (decoration -> active/inactive_opacity,
-- SUPER + O), not in a catch-all rule: in a rule, `fullscreen` can also act
-- as the "force fullscreen" effect.

-- Apps may ask to open maximized (kitty does when it was closed that way).
-- Ignore that so every new window takes its place in the tiling; SUPER + F
-- still makes a window fullscreen.
hl.window_rule({ name = "yakushi-tile-new-windows", match = { class = ".*" }, suppress_event = "maximize" })

-- Small tool windows open floating.
local floating = {
    class = { "pavucontrol", "nm-connection-editor", "blueman-manager" },
    title = { "Open File", "Save File" },
}

for field, names in pairs(floating) do
    for _, value in ipairs(names) do
        hl.window_rule({
            name = "yakushi-float-" .. value:lower():gsub("%s+", "-"),
            match = { [field] = "^(" .. value .. ")$" },
            float = true,
        })
    end
end
