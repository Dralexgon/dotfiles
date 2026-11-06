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

-- razerfx (kitty --class razerfx, from the app launcher) floats centered like nixcfg
hl.window_rule({
    match = {
        class = "^(razerfx)$"
    },
    float = true,
    size = "(monitor_w*0.6) (monitor_h*0.6)",
    center = true,
    fullscreen_state = 0
})

-- File pickers opened through the portal (browsers, Electron apps, flatpaks...) float at a fixed size.
-- Caelestia only sizes some dialog titles: "File Upload" (Zen) floats at the size it asks for, which can be bigger than the screen
hl.window_rule({
    match = {
        class = "^(xdg-desktop-portal-gtk)$"
    },
    float = true,
    size = "(monitor_w*0.5) (monitor_h*0.6)",
    center = true
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

-- SUPER + SHIFT + Return opens kitty with the plain kitty.conf colours (SUPER + Return uses the Caelestia scheme)
hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("kitty"))

hl.window_rule({
    name = "no-kitty-fullscreen",
    match = {
        class = "^kitty$"
    },
    fullscreen_state = 0
})

-- change the icon pack (yaru-magenta, yaru-green, etc...) depending on wallpaper when changing wallpaper with caelestia

-- Mouse pointer trail, a Hyprland plugin (tools/hypr-cursortrail, installed by nixos/modules/caelestia.nix).
-- Follows the Caelestia scheme and hides in game mode. Tunable with
-- hl.config({ plugin = { cursortrail = { width = 8, life_ms = 220, color = 0 } } })
hl.plugin.load("/etc/hypr/plugins/cursortrail.so")

-- Liquid Glass / Acrylic / Mica window effects, a Hyprland plugin (tools/hypr-liquid, installed by
-- nixos/modules/caelestia.nix). Options: https://github.com/zaregototsukai/hyprliquid#configuration
hl.plugin.load("/etc/hypr/plugins/hyprliquid.so")
-- Unknown rule keys abort the file before the plugin is loaded (see the hyprexpo note below)
if hl.plugin.hyprliquid then
    hl.window_rule({
        name = "kitty-liquid-glass",
        match = {
            class = "^kitty$"
        },
        no_blur = true, -- the glass refracts the sharp background (blur hides the effect)
        ["hyprliquid:effect"] = "liquid_glass", -- or acrylic, acrylic_thin, mica, mica_alt, aero
        ["hyprliquid:tint_color"] = "rgba(0x14, 0x0c, 0x1e, 0.45)", -- dark violet, keeps text readable
        ["hyprliquid:highlight_style"] = 2, -- top-left and bottom-right edges
        ["hyprliquid:glass_dispersion"] = true
    })
end

-- Workspace overview on SUPER + Tab: hyprtasking when it builds against the current Hyprland
-- (it often lags behind), else hyprexpo (tools/hypr-expo). Both are installed by nixos/modules/caelestia.nix.
local HYPRTASKING = "/etc/hypr/plugins/hyprtasking/libhyprtasking.so"
local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
    end
    return file ~= nil
end
-- only one of them: both take over the workspace rendering
local use_hyprtasking = file_exists(HYPRTASKING)
hl.plugin.load(use_hyprtasking and HYPRTASKING or "/etc/hypr/plugins/hyprexpo.so")

hl.bind("SUPER + Tab", function()
    if hl.plugin.hyprtasking then
        hl.plugin.hyprtasking.toggle("cursor")
    elseif hl.plugin.hyprexpo then
        hl.plugin.hyprexpo.expo("toggle") -- click a workspace (or SUPER + Tab again) to go there
    end
end)

-- Plugins load after the config runs, then Hyprland runs it again: on the first pass the plugin's
-- config keys and functions do not exist yet (and an unknown key aborts the rest of this file)
if hl.plugin.hyprexpo then
    hl.config({
        plugin = {
            hyprexpo = {
                columns = 3,
                gap_size = 5,
                bg_col = 0xff111111,
                workspace_method = "center current", -- or "first 1"
                skip_empty = 0 -- 1: only workspaces that exist
            }
        }
    })
    -- 4-finger swipe up on a trackpad (3 fingers up/down and 4 down/horizontal are Caelestia's)
    hl.plugin.hyprexpo.gesture(4, "up")
end
