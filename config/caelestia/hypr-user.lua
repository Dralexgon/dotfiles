hl.monitor({
    output = "DP-1", -- your monitor name, use hyprctl monitors
    -- mode = "3840x2160@164.99Hz",
    mode = "3840x2160@60Hz",
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

-- Keyboard layouts: en, en_international, fr. SUPER + SHIFT + Space rolls between them (bind below).
-- Not the xkb option grp:win_space_toggle: xkb fires it on top of the Hyprland binds, it took
-- SUPER + Space from Nova, and binds made by xkb are invisible to `hyprctl binds` (and keybinds-viewer)
hl.config({
    input = {
        sensitivity = -0.1, -- -0.3, -- -0.1,
        kb_layout = "us,us,fr",
        kb_variant = ",intl,",
        kb_options = ""
    }
})

hl.bind("SUPER + SHIFT + Space", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"), { description = "Next keyboard layout" })

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

-- keybinds-viewer (SUPER + /, tools/keybinds-viewer) floats centered like nixcfg, a bit bigger for the keyboard
hl.window_rule({
    match = {
        class = "^(dev\\.dralexgon\\.KeybindsViewer)$"
    },
    float = true,
    size = "(monitor_w*0.8) (monitor_h*0.85)",
    center = true
})

-- rice-picker ("Rices" in the app launcher, tools/rice-picker) floats centered
hl.window_rule({
    match = {
        class = "^(dev\\.dralexgon\\.RicePicker)$"
    },
    float = true,
    size = "980 380",
    center = true
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
end, { description = "nixcfg" })

-- Nova (voice AI companion, ~/dev/ai/nova): a Quickshell overlay driven by her own backend
-- SUPER + A opens Nova, then switches her between full screen and the mini orb (top right)
hl.bind("SUPER + A", hl.dsp.exec_cmd("sh -c 'curl -sf -X POST http://127.0.0.1:8765/api/toggle || exec ~/dev/ai/nova/run.sh'"), { description = "Nova (open / toggle)" })

-- SUPER + Space talks to Nova from anywhere, like Space in her window: hold it and she sends when
-- you let go, or tap it and she listens until the next press (the logic is in Nova.ptt())
hl.bind("SUPER + Space", hl.dsp.exec_cmd("curl -s -X POST http://127.0.0.1:8765/api/talk-down"), { description = "Talk to Nova (tap or hold)" })
hl.bind("SUPER + Space", hl.dsp.exec_cmd("curl -s -X POST http://127.0.0.1:8765/api/talk-up"), { release = true })

-- SUPER + SHIFT + Return opens kitty with the plain kitty.conf colours (SUPER + Return uses the Caelestia scheme)
hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("kitty"), { description = "Kitty (plain colours)" })

-- SUPER + / shows the keyboard with all these shortcuts (tools/keybinds-viewer). The descriptions given
-- to hl.bind are the names it shows; Caelestia's own binds are named from their kb* variables
hl.bind("SUPER + Slash", hl.dsp.exec_cmd("keybinds-viewer"), { description = "Keyboard shortcuts" })

hl.window_rule({
    name = "no-kitty-fullscreen",
    match = {
        class = "^kitty$"
    },
    fullscreen_state = 0
})

-- change the icon pack (yaru-magenta, yaru-green, etc...) depending on wallpaper when changing wallpaper with caelestia

-- Mouse pointer trail, a Hyprland plugin (tools/hypr-cursortrail, installed by nixos/modules/desktop/caelestia.nix).
-- Follows the Caelestia scheme and hides in game mode. Tunable with
-- hl.config({ plugin = { cursortrail = { width = 8, life_ms = 220, color = 0 } } })
hl.plugin.load("/etc/hypr/plugins/cursortrail.so")
-- Its colour is set by the rice (see "Rices" below)

-- Closing / opening window animations, a Hyprland plugin (tools/hypr-windowfx, installed by
-- nixos/modules/desktop/caelestia.nix). It replaces windowsOut / windowsIn for those windows and stays off in game mode.
--  petals: closing windows shatter into petals blown away by the wind, opening ones assemble from petals.
--  blood:  closing windows shrink to nothing at their centre and burst into blood droplets (cursorfx's
--          drops); opening windows pop in from 50% (like windowsIn), then drops drip off their edges.
--  blood-legacy: blood runs down closing windows, then they splash away in droplets; opening windows
--          rise from the drops and the blood runs off them.
-- Switch live with hyprctl eval 'hl.config({ plugin = { windowfx = { style = "petals" } } })'   (petals | blood | blood-legacy | off)
-- Tunable with hl.config({ plugin = { windowfx = { max_pieces = 240, open = 1, open_duration_ms = 900,
-- open_spread_ms = 280, open_delay_ms = 60, open_refresh_ms = 80, open_speed = 1.0,
-- size = 44, duration_ms = 1700, spread_ms = 380, wind_x = 1.0, wind_y = -0.45, wind_strength = 750, tint = 0.3, color = 0,
-- blood_color = 0xFF8A0012, blood_size = 0 (0 = cursorfx's size), blood_close_ms = 120, blood_open_ms = 450,
-- blood_drops = 40, blood_drips = 1.0, blood_gravity = 1600, blood_splat = 1, blood_splat_ms = 1600,
-- blood_legacy_size = 18, blood_legacy_max_drops = 1500, blood_legacy_duration_ms = 1000, blood_legacy_spread_ms = 420,
-- blood_legacy_gravity = 1900 } } })
hl.plugin.load("/etc/hypr/plugins/windowfx.so")

-- Blood. open_speed only speeds up the petals' opening; the hidden wait before an opening window shows
-- and its snapshot refresh are halved for both styles (60 / 80 ms).
-- The plugin's keys do not exist on the first config pass (see the hyprexpo note below), and windowfx has
-- no hl.plugin.windowfx table to test, so pcall keeps the error from aborting the rest of this file
pcall(hl.config, {
    plugin = {
        windowfx = {
            open_speed = 2.0,
            open_delay_ms = 30,
            open_refresh_ms = 40
        }
    }
})

-- Petals, blood drops or images thrown behind the mouse pointer, a Hyprland plugin (tools/hypr-cursorfx,
-- installed by nixos/modules/desktop/caelestia.nix). Stays off in game mode. Switch live with
-- hyprctl eval 'hl.config({ plugin = { cursorfx = { style = "blood" } } })'   (petals | blood | image | off)
-- Tunable with hl.config({ plugin = { cursorfx = { style = "petals", image = "~/Pictures/bat.png", density = 5,
-- size = 14, life_ms = 1400, max_particles = 400, color = 0, blood_color = 0xFF8A0012, splat_ms = 1600 } } })
-- (wrap it in pcall like windowfx above: the keys do not exist on the first config pass)
hl.plugin.load("/etc/hypr/plugins/cursorfx.so")
-- Its style is set by the rice (see "Rices" below)

-- Rices: one Caelestia scheme + the windowfx / cursorfx / cursortrail looks that go with it, and
-- a wallpaper for the fixed schemes (adaptive keeps the current one, its colours come from it).
-- SUPER + SHIFT + R cycles adaptive -> petals -> vampire; `rice <name>` (user-config.fish) or the
-- "Rices" app (tools/rice-picker, keep its RICES list in sync) picks one.
-- The choice is kept in ~/.local/state/caelestia/rice, so a config reload or a new session keeps it
-- (Caelestia remembers the scheme by itself, only the plugins are reapplied then).
local RICE_STATE = (os.getenv("HOME") or "") .. "/.local/state/caelestia/rice"
local RICE_ORDER = { "adaptive", "petals", "vampire" }
local WALLPAPERS = "$HOME/Pictures/Wallpapers/Safe/" -- not in the dotfiles; expanded by the shell
local RICES = {
    -- colours from the wallpaper: only the trail, in the scheme colour (color = 0), and Hyprland's
    -- own window animations (no petals, no blood)
    adaptive = {
        scheme = "caelestia scheme set -n dynamic",
        windowfx = "off",
        cursorfx = "off",
        trail = 0
    },
    -- pink and soft: config/caelestia/schemes/petals
    petals = {
        scheme = "caelestia scheme set -n petals -f soft -m dark",
        wallpaper = "Sakura_4k.png",
        windowfx = "petals",
        cursorfx = "petals",
        trail = 0
    },
    -- bright red and bloody: config/caelestia/schemes/vampire, trail red like the cursorfx blood
    vampire = {
        scheme = "caelestia scheme set -n vampire -f hard -m dark",
        wallpaper = "Konachan.com - 228944 blood close collar fang krul_tepes long_hair owari_no_seraph pink_eyes pink_hair pointed_ears rinfiora vampire_upscayl_4x_upscayl-standard-4x.png",
        windowfx = "blood",
        cursorfx = "blood",
        trail = 0xFF8A0012
    }
}

local function read_rice()
    local file = io.open(RICE_STATE, "r")
    local name = file and file:read("l")
    if file then
        file:close()
    end
    return RICES[name] and name or "vampire"
end

-- pcall: the plugins' keys do not exist on the first config pass
local function apply_rice_plugins(name)
    local rice = RICES[name]
    pcall(hl.config, { plugin = { windowfx = { style = rice.windowfx } } })
    pcall(hl.config, { plugin = { cursorfx = { style = rice.cursorfx } } })
    pcall(hl.config, { plugin = { cursortrail = { color = rice.trail } } })
end

-- Global, so `hyprctl eval 'set_rice("petals")'` can call it ("next" cycles)
function set_rice(name)
    if name == "next" then
        local current = read_rice()
        for i, n in ipairs(RICE_ORDER) do
            if n == current then
                name = RICE_ORDER[i % #RICE_ORDER + 1]
            end
        end
    end
    local rice = RICES[name]
    if not rice then
        error("unknown rice " .. tostring(name) .. " (adaptive | petals | vampire | next)")
    end
    local file = io.open(RICE_STATE, "w")
    if file then
        file:write(name, "\n")
        file:close()
    end
    apply_rice_plugins(name)
    local cmd = rice.scheme
    if rice.wallpaper then
        -- after the scheme, so it is no longer dynamic; -N: a bright wallpaper must not flip the mode to light
        cmd = cmd .. ' && caelestia wallpaper -N -f "' .. WALLPAPERS .. rice.wallpaper .. '"'
    end
    hl.dispatch(hl.dsp.exec_cmd(cmd .. " && notify-send -a caelestia -t 2000 'Rice' '" .. name .. "'"))
end

apply_rice_plugins(read_rice())
hl.bind("SUPER + SHIFT + R", function()
    set_rice("next")
end, { description = "Next rice" })

-- Liquid Glass / Acrylic / Mica window effects, a Hyprland plugin (tools/hypr-liquid, installed by
-- nixos/modules/desktop/caelestia.nix). Options: https://github.com/zaregototsukai/hyprliquid#configuration
-- hl.plugin.load("/etc/hypr/plugins/hyprliquid.so")
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
-- (it often lags behind), else hyprexpo (tools/hypr-expo). Both are installed by nixos/modules/desktop/caelestia.nix.
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
end, { description = "Workspace overview" })

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
