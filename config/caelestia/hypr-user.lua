hl.monitor({
    output = "DP-2", -- your monitor name, use hyprctl monitors
    mode = "3840x2160@164.99Hz",
    position = "0x0",
    scale = 1.5
})

-- Overshoot curve ("easeOutBack"): goes past 1.0, then settles back
hl.curve("windowPop", {
    type = "bezier",
    points = {{0.34, 1.56}, {0.64, 1}}
})

hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 4.5,
    bezier = "windowPop",
    style = "popin 50%"
})

hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 1.49,
    bezier = "linear",
    style = "popin 55%"
})

hl.config({
    xwayland = {
        force_zero_scaling = true -- avoid pixelated game when using scale = 1.5 on monitors
    }
})

-- change keyboard by using SUPER + space, rolling between : en, en_international, fr
hl.config({
    input = {
        sensitivity = -0.1, -- -0.3, -- -0.1,
        kb_layout = "us,us,fr",
        kb_variant = ",intl,",
        kb_options = "grp:win_space_toggle"
    }
})

hl.config({
    env = {"QS_ICON_THEME,Yaru-magenta-dark"}
})

hl.window_rule({
    match = {
        class = "^(Albion-Online)$"
    },
    float = true,
    size = {3840, 1620}
})

-- nixcfg (kitty --class nixcfg) floats centered above windows, like Caelestia settings but a bit smaller
hl.window_rule({
    match = {
        class = "^(nixcfg)$"
    },
    float = true,
    size = "(monitor_w*0.75) (monitor_h*0.75)",
    center = true,
    fullscreen_state = 0 -- kitty asks to be maximized, which would override the size
})

-- SUPER + I opens nixcfg, or focuses it if it is already open
hl.bind("SUPER + I", function()
    for _, window in ipairs(hl.get_windows() or {}) do
        if window.class == "nixcfg" then
            return hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
        end
    end
    hl.dispatch(hl.dsp.exec_cmd("kitty --class nixcfg --title nixcfg nixcfg"))
end)

hl.window_rule({
    name = "no-kitty-fullscreen",
    match = {
        class = "^kitty$"
    },
    fullscreen_state = 0
})

-- change the icon pack (yaru-magenta, yaru-green, etc...) depending on wallpaper when changing wallpaper with caelestia
