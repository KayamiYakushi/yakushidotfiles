-- Yakushi · monitors
-- Every screen at its preferred mode; Settings -> Monitors saves the real
-- layout of this machine in monitors.local.lua (not tracked by git).
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

pcall(dofile, os.getenv("HOME") .. "/.config/hypr/monitors.local.lua")
