-- Portable default monitor rule.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- Yakushi monitor layout

-- Load per-machine monitor overrides when present.
local yakushi_home = os.getenv("HOME")
pcall(dofile, yakushi_home .. "/.config/hypr/monitors.local.lua")
