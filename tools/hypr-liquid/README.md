# hypr-liquid

Nix packaging of [hyprliquid](https://github.com/zaregototsukai/hyprliquid) (by zaregototsukai, BSD-3-Clause):
Liquid Glass, Acrylic, Mica and Aero material effects for Hyprland windows. The source is the `hyprliquid` flake input.

`nixos/modules/desktop/caelestia.nix` installs it as `/etc/hypr/plugins/hyprliquid.so`.
In `config/caelestia/hypr-user.lua` the `hl.plugin.load` line is **commented out**, so it is off by default.
Uncomment it to get the `kitty-liquid-glass` window rule: Liquid Glass with a dark violet tint on kitty.

## Tips

- The glass only bends the background near the edges, in a band as wide as the corner rounding (15 px by default, so it barely shows).
  For a stronger look, add `["hyprliquid:rounding_lua"] = 64` to the rule: the normal `rounding` rule is capped at 20 in Lua.
- Keep `no_blur = true` on the rule: with Hyprland's blur it looks frosted, not like glass.
- Effects: `liquid_glass`, `acrylic`, `acrylic_thin`, `mica`, `mica_alt`, `aero`. Every option is in [hyprliquid's README](https://github.com/zaregototsukai/hyprliquid#configuration).

Built against `pkgs.hyprland`: rebuild after a Hyprland update.
