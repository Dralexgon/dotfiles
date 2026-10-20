#!/usr/bin/env bash
exec >>/tmp/set-icons.log 2>&1
echo "--- $(date) hook ran ---"

scheme_out=$(caelestia scheme get 2>&1)

read -r theme mode < <(python3 - "$scheme_out" <<'EOF'
import re, sys, colorsys

text = re.sub(r"\x1b\[[0-9;]*m", "", sys.argv[1])  # strip color codes if any

m_mode = re.search(r"^\s*Mode:\s*(\w+)", text, re.M)
m_primary = re.search(r"^\s*primary:\s*#?([0-9a-fA-F]{6})\s*$", text, re.M)
if not m_primary:
    print("could not parse primary from caelestia scheme get", file=sys.stderr)
    sys.exit(1)

mode = m_mode.group(1).lower() if m_mode else "dark"
primary = m_primary.group(1)
rgb = tuple(int(primary[i:i+2], 16) for i in (0, 2, 4))

def hue(c):
    h, s, v = colorsys.rgb_to_hsv(*(x / 255 for x in c))
    return h * 360, s

variants = {
    "Yaru":               (0xE9, 0x54, 0x20),
    "Yaru-wartybrown":    (0xB5, 0x83, 0x5A),
    "Yaru-yellow":        (0xF6, 0xD3, 0x2D),
    "Yaru-bark":          (0x78, 0x78, 0x59),
    "Yaru-sage":          (0x65, 0x7B, 0x69),
    "Yaru-olive":         (0x4B, 0x85, 0x01),
    "Yaru-viridian":      (0x03, 0x87, 0x5B),
    "Yaru-prussiangreen": (0x30, 0x82, 0x80),
    "Yaru-blue":          (0x00, 0x73, 0xE5),
    "Yaru-purple":        (0x77, 0x64, 0xD8),
    "Yaru-magenta":       (0xB3, 0x4C, 0xB3),
    "Yaru-red":           (0xDA, 0x34, 0x50),
}

h, s = hue(rgb)
if s < 0.12:
    name = "Yaru-sage"
else:
    circ = lambda a, b: min(abs(a - b), 360 - abs(a - b))
    name = min(variants, key=lambda k: circ(h, hue(variants[k])[0]))

print(f"primary={primary} hue={h:.0f} sat={s:.2f} -> {name} ({mode})", file=sys.stderr)

if mode == "dark":
    name += "-dark"
print(name, mode)
EOF
)

echo "theme=$theme mode=$mode"
[ -z "${theme:-}" ] && { echo "Python step failed"; exit 1; }

gsettings set org.gnome.desktop.interface icon-theme "$theme"

if [ "$mode" = "dark" ]; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
else
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
fi

# GTK ini files (only regular, writable files)
for f in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
    if [ -f "$f" ] && [ ! -L "$f" ]; then
        if grep -q '^gtk-icon-theme-name=' "$f"; then
            sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$theme/" "$f"
        else
            sed -i "/^\[Settings\]/a gtk-icon-theme-name=$theme" "$f"
        fi
    fi
done

# Qt apps (qtengine)
QTE="$HOME/.config/qtengine/config.json"
if [ -f "$QTE" ] && [ ! -L "$QTE" ]; then
    python3 - "$QTE" "$theme" <<'EOF'
import json, sys, os
path, theme = sys.argv[1], sys.argv[2]
data = json.load(open(path))
if isinstance(data.get("theme"), dict) and "iconTheme" in data["theme"]:
    data["theme"]["iconTheme"] = theme
    tmp = path + ".tmp"
    json.dump(data, open(tmp, "w"), indent=4)
    os.replace(tmp, path)
else:
    print("qtengine: theme.iconTheme key not found, skipped", file=sys.stderr)
EOF
fi

# Nautilus loads gtk.css only at startup, so restart it to apply the new colors

