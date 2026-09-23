-- ~/.config/hypr/rules.lua
-- Migrated from rules.conf
-- Docs: https://wiki.hypr.land/Configuring/Basics/Window-Rules/

hl.layer_rule({
    match = { namespace = "rofi" },
    blur = true,
    ignore_alpha = 0.15,
})

-- Opacity rules: 90% for all windows except fullscreen
hl.window_rule({
    match = { class = ".*" },
    opacity = "1.0 override",
})

hl.window_rule({
    match = { class = ".*", fullscreen = true },
    opacity = "1.0 override",
})

hl.window_rule({
    name = "float-pavucontrol",
    match = { class = "^(pavucontrol)$" },
    float = true,
})

hl.window_rule({
    name = "float-nm-connection-editor",
    match = { class = "^(nm-connection-editor)$" },
    float = true,
})

hl.window_rule({
    name = "float-blueman-manager",
    match = { class = "^(blueman-manager)$" },
    float = true,
})

hl.window_rule({
    name = "float-open-file",
    match = { title = "^(Open File)$" },
    float = true,
})

hl.window_rule({
    name = "float-save-file",
    match = { title = "^(Save File)$" },
    float = true,
})

-- Yakushi Settings file pickers
hl.window_rule({
    name = "yakushi-login-background-picker",
    match = { title = "^(Choose Login Screen Background)$" },
    float = true,
    center = true,
    size = { 980, 640 },
})

hl.window_rule({
    name = "yakushi-system-image-picker",
    match = { title = "^(Choose System Image)$" },
    float = true,
    center = true,
    size = { 980, 640 },
})

-- Yakushi custom image picker
hl.window_rule({
    name = "float-yakushi-image-picker",
    match = { title = "^(Yakushi Image Picker)$" },
    float = true,
    center = true,
    size = { 980, 640 },
})
