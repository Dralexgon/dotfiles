return {
  -- Changing default apps:
  terminal          = "foot",
  browser          = "zen-beta",    -- Change default browser to Zen
  editor           = "codium",           -- Change default editor to Code
  fileExplorer               = "nautilus",

  -- Changing window/decoration properties:
  windowBorderSize = 2,                -- Increase window border size (default: 1)
  windowGapsIn               = 5,
  windowGapsOut              = 10,
  singleWindowGapsOut        = 20,

  cursorTheme                = "sweet-cursors",

  -- Changing keybinds:
  kbTerminal       = "SUPER + Return", -- Change the keybind for opening terminal
  kbMoveWinToWs              = "SUPER + SHIFT",
  kbBrowser                  = "SUPER + W",
  kbCloseWindow              = "SUPER + SHIFT + Q",
  kbResizeWindow             = "SUPER + mouse:273", -- right click
}
