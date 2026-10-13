hl.monitor({
  output   = "DP-2",   -- your monitor name, use hyprctl monitors
  mode     = "preferred",
  position = "0x0",
  scale    = 1.5,
})

-- Overshoot curve ("easeOutBack"): goes past 1.0, then settles back
hl.curve("windowPop", { type = "bezier", points = { {0.34, 1.56}, {0.64, 1} } })

hl.animation({
  leaf    = "windowsIn",
  enabled = true,
  speed   = 4.5,
  bezier  = "windowPop",
  style   = "popin 50%",
})

hl.animation({
  leaf    = "windowsOut",
  enabled = true,
  speed   = 1.49,
  bezier  = "linear",
  style   = "popin 55%",
})

-- change keyboard by using SUPER + space, rolling between : en, en_international, fr

-- change the icon pack (yaru-magenta, yaru-green, etc...) depending on wallpaper when changing wallpaper with caelestia
