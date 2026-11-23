hl.monitor({
    output = "DP-1", -- your monitor name, use hyprctl monitors
    mode = "3840x2160@164.99Hz",
    -- mode = "3840x2160@60Hz",
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

-- Don't switch DP-1 to HDR when a fullscreen app asks for it (VSCodium on SUPER + F did): the monitor
-- changes mode, goes black for a few seconds and shows its "HDR" popup
hl.config({
    render = {
        cm_auto_hdr = 0
    }
})

-- Keyboard layouts: en, en_international, fr. SUPER + Space rolls between them (bind below).
-- Not the xkb option grp:win_space_toggle: xkb fires it on top of the Hyprland binds,
-- and binds made by xkb are invisible to `hyprctl binds` (and keybinds-viewer)
-- us must stay the FIRST layout: Hyprland also matches binds against the first layout's keysyms,
-- which is what keeps the QWERTY-written binds (SUPER + 1, Slash...) working while typing in fr.
-- The laptop (AZERTY keyboard) just switches to fr (index 2) at startup instead.
local function read_hostname()
    local file = io.open("/etc/hostname", "r")
    if not file then return "" end
    local name = file:read("*l") or ""
    file:close()
    return name
end

if read_hostname() == "nixos-gray-laptop" then
    hl.on("hyprland.start", function()
        hl.exec_cmd("hyprctl switchxkblayout all 2")
    end)
end

hl.config({
    input = {
        sensitivity = -0.1, -- -0.3, -- -0.1,
        kb_layout = "us,us,fr",
        kb_variant = ",intl,",
        kb_options = ""
    }
})

hl.bind("SUPER + Space", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"), { description = "Next keyboard layout" })

hl.window_rule({
    match = {
        class = "^(Albion-Online)$"
    },
    float = true,
    size = {3840, 1620}
})

-- nixcfg (kitty --class nixcfg) floats centered above windows, like Caelestia settings but a bit smaller
-- (nixcfg-legacy is its old Python version, nix run ~/dotfiles#nixcfg-legacy)
hl.window_rule({
    match = {
        class = "^(nixcfg|nixcfg-legacy)$"
    },
    float = true,
    size = "(monitor_w*0.75) (monitor_h*0.75)",
    center = true,
    fullscreen_state = 0 -- kitty asks to be maximized, which would override the size
})

-- nixcfg lives on its own special workspace, so it is hidden and shown again (SUPER + I, its tray
-- icon, Escape in nixcfg) instead of closed and reopened: showing it is instant, no new kitty
hl.window_rule({
    match = {
        class = "^(nixcfg)$"
    },
    workspace = "special:nixcfg"
})

-- rgbfx (its GTK window) floats centered like nixcfg
hl.window_rule({
    match = {
        class = "^(dev\\.dralexgon\\.rgbfx)$"
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

-- SUPER + I shows nixcfg (its special workspace), or hides it when it is shown. Without a window
-- yet it starts one there, like Caelestia's special workspaces (tools/nixcfg/src/window.rs does the same)
hl.bind("SUPER + I", function()
    local active = hl.get_active_special_workspace()
    if active and active.name == "special:nixcfg" then
        return hl.dispatch(hl.dsp.workspace.toggle_special("nixcfg"))
    end
    for _, window in ipairs(hl.get_windows() or {}) do
        if window.class == "nixcfg" then
            if window.workspace and window.workspace.name == "special:nixcfg" then
                hl.dispatch(hl.dsp.focus({ workspace = "special:nixcfg" }))
            end
            return hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
        end
    end
    hl.dispatch(hl.dsp.focus({ workspace = "special:nixcfg" }))
    hl.dispatch(hl.dsp.exec_cmd("kitty --class nixcfg --title nixcfg nixcfg", { workspace = "special:nixcfg" }))
end, { description = "nixcfg (show / hide)" })

-- Nova (voice AI companion, ~/dev/ai/nova): a Quickshell overlay driven by her own backend
-- SUPER + A opens Nova, then switches her between full screen and the mini orb (top right)
hl.bind("SUPER + A", hl.dsp.exec_cmd("sh -c 'curl -sf -X POST http://127.0.0.1:8765/api/toggle || exec ~/dev/ai/nova/run.sh'"), { description = "Nova (open / toggle)" })

-- F8 talks to Nova from anywhere, like Space in her window: hold it and she sends when
-- you let go, or tap it and she listens until the next press (the logic is in Nova.ptt())
hl.bind("F8", hl.dsp.exec_cmd("curl -s -X POST http://127.0.0.1:8765/api/talk-down"), { description = "Talk to Nova (tap or hold)" })
hl.bind("F8", hl.dsp.exec_cmd("curl -s -X POST http://127.0.0.1:8765/api/talk-up"), { release = true })

-- SUPER + SHIFT + Return opens kitty with the plain kitty.conf colours (SUPER + Return uses the Caelestia scheme)
hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("kitty"), { description = "Kitty (plain colours)" })

-- SUPER + ALT + C opens Claude Code in kitty, in ~/dotfiles (trusted, unlike ~, so no trust prompt every time).
-- A shell stays open after Claude exits. SUPER + C is Caelestia's editor bind (VSCodium, hypr-vars.lua)
-- Claude's colours (orange on warm dark) from config/kitty/claude.conf, on top of kitty.conf. Its own class
-- keeps it out of the kitty rules (liquid glass) and lets the rule below make it fully opaque
hl.bind("SUPER + ALT + C", hl.dsp.exec_cmd([[kitty --class claude --config ~/.config/kitty/kitty.conf --config ~/.config/kitty/claude.conf --directory ~/dotfiles bash -lc 'claude; exec bash']]), { description = "Claude Code" })

-- No transparency for the Claude window: overrides Caelestia's 0.95 opacity on every window (active / inactive)
hl.window_rule({
    match = {
        class = "^(claude)$"
    },
    opacity = "1.0 override",
    no_blur = true,
    fullscreen_state = 0 -- like the kitty rule below: kitty asks to be maximized
})

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

-- Rices: one file per rice in ~/.config/caelestia/rices/<name>.json (config/caelestia/rices, see its
-- README): a Caelestia scheme, a wallpaper, the cursor and fonts, and the windowfx / cursorfx /
-- cursortrail looks and window animations that go with it. A new file there is a new rice.
-- SUPER + SHIFT + R cycles them (by their "order"); `rice <name>` (user-config.fish) or the
-- "Rices" app (tools/rice-picker, which also edits them) picks one.
-- Here: the Hyprland side (plugins, animations, transition). `rice-picker --apply <name>` does the
-- rest (scheme, wallpaper, cursor, fonts).
-- The choice is kept in ~/.local/state/caelestia/rice, so a config reload or a new session keeps it
-- (Caelestia remembers the scheme by itself, only the Hyprland side is reapplied then).
local HOME = os.getenv("HOME") or ""
local RICE_STATE = HOME .. "/.local/state/caelestia/rice"
local RICES_DIR = HOME .. "/.config/caelestia/rices/"
local DEFAULT_RICE = "vampire"

-- Hyprland's Lua has no JSON library: a small decoder, enough for the rice files
local function json_decode(text)
    local pos = 1
    local value
    local function skip()
        pos = text:find("[^ \t\r\n]", pos) or #text + 1
    end
    local function fail(what)
        error("rice json: " .. what .. " at " .. pos)
    end
    local function str()
        local out = {}
        pos = pos + 1
        while true do
            local c = text:sub(pos, pos)
            if c == "" then
                fail("unfinished string")
            elseif c == '"' then
                pos = pos + 1
                return table.concat(out)
            elseif c == "\\" then
                local e = text:sub(pos + 1, pos + 1)
                local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
                if e == "u" then
                    out[#out + 1] = utf8.char(tonumber(text:sub(pos + 2, pos + 5), 16))
                    pos = pos + 6
                else
                    out[#out + 1] = map[e] or e
                    pos = pos + 2
                end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
    end
    function value()
        skip()
        local c = text:sub(pos, pos)
        if c == "{" then
            local obj = {}
            pos = pos + 1
            skip()
            if text:sub(pos, pos) == "}" then
                pos = pos + 1
                return obj
            end
            while true do
                skip()
                if text:sub(pos, pos) ~= '"' then
                    fail("expected a key")
                end
                local k = str()
                skip()
                if text:sub(pos, pos) ~= ":" then
                    fail("expected ':'")
                end
                pos = pos + 1
                obj[k] = value()
                skip()
                c = text:sub(pos, pos)
                pos = pos + 1
                if c == "}" then
                    return obj
                elseif c ~= "," then
                    fail("expected ',' or '}'")
                end
            end
        elseif c == "[" then
            local arr = {}
            pos = pos + 1
            skip()
            if text:sub(pos, pos) == "]" then
                pos = pos + 1
                return arr
            end
            while true do
                arr[#arr + 1] = value()
                skip()
                c = text:sub(pos, pos)
                pos = pos + 1
                if c == "]" then
                    return arr
                elseif c ~= "," then
                    fail("expected ',' or ']'")
                end
            end
        elseif c == '"' then
            return str()
        elseif text:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif text:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif text:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end
        local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        if not num or num == "" then
            fail("unexpected '" .. c .. "'")
        end
        pos = pos + #num
        return tonumber(num)
    end
    return value()
end

-- Every rice file, by name; a broken file is skipped (and named in the error log)
local function load_rices()
    local rices = {}
    local list = io.popen('ls -1 "' .. RICES_DIR .. '" 2>/dev/null')
    for file in (list and list:lines() or function() end) do
        local name = file:match("^(.+)%.json$")
        local f = name and io.open(RICES_DIR .. file, "r")
        if f then
            local ok, rice = pcall(json_decode, f:read("a"))
            f:close()
            if ok and type(rice) == "table" then
                rices[name] = rice
            else
                print("rice " .. name .. ": " .. tostring(rice))
            end
        end
    end
    if list then
        list:close()
    end
    return rices
end

local function rice_order(rices)
    local names = {}
    for name in pairs(rices) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b)
        local oa, ob = rices[a].order or math.huge, rices[b].order or math.huge
        if oa ~= ob then
            return oa < ob
        end
        return a < b
    end)
    return names
end

local function read_rice(rices)
    local file = io.open(RICE_STATE, "r")
    local name = file and file:read("l")
    if file then
        file:close()
    end
    if rices[name] then
        return name
    end
    return rices[DEFAULT_RICE] and DEFAULT_RICE or rice_order(rices)[1]
end

-- "#8A0012" -> 0xFF8A0012; nil -> 0 (the plugin then takes the scheme colour)
local function argb(hex)
    local rgb = type(hex) == "string" and hex:match("^#?(%x%x%x%x%x%x)$")
    return rgb and tonumber("FF" .. rgb, 16) or 0
end

-- pcall: the plugins' keys do not exist on the first config pass
local function apply_rice_hypr(rice)
    pcall(hl.config, { plugin = { windowfx = { style = rice.windowfx or "off" } } })
    pcall(hl.config, { plugin = { cursorfx = { style = rice.cursorfx or "off" } } })
    pcall(hl.config, { plugin = { cursortrail = { color = argb(rice.trail) } } })
    for leaf, anim in pairs(rice.animations or {}) do
        pcall(hl.animation, {
            leaf = leaf,
            enabled = anim.enabled ~= false,
            speed = anim.speed,
            bezier = anim.bezier,
            style = anim.style
        })
    end
end

-- The login screen follows the rice (themes/sddm/rice): it can't read the home folder, so leave an
-- empty file named after the rice in /var/lib/login-rice (made by nixos/modules/desktop/default.nix)
local LOGIN_RICE = "/var/lib/login-rice/"
local function sync_login_rice(name)
    local list = io.popen('ls -1 "' .. LOGIN_RICE .. '" 2>/dev/null')
    for file in (list and list:lines() or function() end) do
        if file ~= name then
            os.remove(LOGIN_RICE .. file)
        end
    end
    if list then
        list:close()
    end
    local file = io.open(LOGIN_RICE .. name, "w")
    if file then
        file:close()
    end
end

-- Global, so `hyprctl eval 'set_rice("petals")'` can call it ("next" cycles). The files are read
-- again on every switch, so edits (or new rices) apply without a config reload
function set_rice(name)
    local rices = load_rices()
    if name == "next" then
        local order = rice_order(rices)
        local current = read_rice(rices)
        for i, n in ipairs(order) do
            if n == current then
                name = order[i % #order + 1]
            end
        end
    end
    local rice = rices[name]
    if not rice then
        error("unknown rice " .. tostring(name) .. " (" .. table.concat(rice_order(rices), " | ") .. " | next)")
    end
    local file = io.open(RICE_STATE, "w")
    if file then
        file:write(name, "\n")
        file:close()
    end
    -- The rice's transition effect over the screen while the colours and the wallpaper change
    -- behind it; first, so it is already playing when the scheme switches
    if rice.transition then
        hl.dispatch(hl.dsp.exec_cmd(rice.transition))
    end
    apply_rice_hypr(rice)
    sync_login_rice(name)
    hl.dispatch(hl.dsp.exec_cmd("rice-picker --apply '" .. name:gsub("'", "") .. "'"))
end

do
    local rices = load_rices()
    local current = read_rice(rices)
    if current then
        apply_rice_hypr(rices[current])
        sync_login_rice(current)
    end
end
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
