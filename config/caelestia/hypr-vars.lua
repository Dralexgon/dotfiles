return {
    -- Changing default apps:
    -- Kitty with the Caelestia colour scheme (same trick as Caelestia's fish config: print the scheme's colour sequences, then start the shell)
    terminal             = [[kitty sh -c 'cat ~/.local/state/caelestia/sequences.txt 2>/dev/null; exec bash']], -- default terminal : foot
    browser              = "zen-beta", -- Change default browser to Zen
    editor               = [[sh -c 'command -v codium >/dev/null && exec codium || exec code']], -- VSCodium, or VS Code if it's missing
    fileExplorer         = "nautilus --new-window",

    -- Changing window/decoration properties:
    windowBorderSize     = 2, -- Increase window border size (default: 1)
    windowGapsIn         = 5,
    windowGapsOut        = 10,
    singleWindowGapsOut  = 10,

    cursorTheme          = "Bibata-Modern-Classic", -- same pointer as nixos/modules/cursors.nix
    cursorSize           = 24,

    -- Changing keybinds:
    kbTerminal           = "SUPER + Return", -- Change the keybind for opening terminal
    kbMoveWinToWs        = "SUPER + SHIFT",
    kbBrowser            = "SUPER + W",
    kbEditor             = "SUPER + C", -- Claude Code is on SUPER + ALT + C (hypr-user.lua)
    kbCloseWindow        = "SUPER + SHIFT + Q",
    kbResizeWindow       = "SUPER + mouse:273" -- right click
}
