"""Build an icon theme whose Yaru folders use exactly the Caelestia primary.

Usage: caelestia-recolor-folders <base Yaru theme> <primary hex> <out dir>

The dominant tone of the base folder icon is mapped exactly onto the primary
(hue shifted, saturation and value remapped piecewise-linearly so 0 and 1 stay
fixed), which keeps Yaru's shading. White and grey pixels are left untouched.
"""

import colorsys
import os
import re
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image

ICON_DIRS = [
    os.path.expanduser("~/.local/share/icons"),
    "/run/current-system/sw/share/icons",
]
FOLDER_ICON = re.compile(
    r"^(folder.*|inode-directory|insync-folder|user-home|user-desktop)\.png$"
)


def find_theme(name):
    for d in ICON_DIRS:
        path = os.path.join(d, name)
        if os.path.isfile(os.path.join(path, "index.theme")):
            return os.path.realpath(path)
    sys.exit(f"icon theme {name} not found")


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    v = rgb.max(-1)
    c = v - rgb.min(-1)
    s = np.where(v > 0, c / np.maximum(v, 1e-9), 0)
    cz = np.maximum(c, 1e-9)
    h = np.select(
        [c == 0, v == r, v == g],
        [0, ((g - b) / cz) % 6, (b - r) / cz + 2],
        (r - g) / cz + 4,
    ) / 6
    return h, s, v


def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    r = np.choose(i, [v, q, p, p, t, v])
    g = np.choose(i, [t, v, v, q, p, p])
    b = np.choose(i, [p, p, t, v, v, q])
    return np.stack([r, g, b], -1)


def remap(x, src, dst):
    """Piecewise-linear map with 0->0, src->dst, 1->1."""
    src = min(max(src, 1e-3), 1 - 1e-3)
    return np.where(
        x <= src,
        x * dst / src,
        dst + (x - src) * (1 - dst) / (1 - src),
    )


def dominant_colour(path):
    px = np.asarray(Image.open(path).convert("RGBA")).reshape(-1, 4)
    px = px[px[:, 3] > 250, :3]
    _, s, _ = rgb_to_hsv(px / 255)
    px = px[s > 0.2]
    colours, counts = np.unique(px, axis=0, return_counts=True)
    return colours[counts.argmax()] / 255


def recolour(src, dst, base, target):
    img = np.asarray(Image.open(src).convert("RGBA")).astype(float) / 255
    h, s, v = rgb_to_hsv(img[..., :3])
    bh, bs, bv = colorsys.rgb_to_hsv(*base)
    th, ts, tv = colorsys.rgb_to_hsv(*target)

    nh = (h + th - bh) % 1
    ns = remap(s, bs, ts)
    nv = remap(v, bv, tv)
    out = hsv_to_rgb(nh, ns, nv)

    # Only tint coloured pixels, so white/grey glyphs keep their look
    w = np.clip((s - 0.08) / 0.15, 0, 1)[..., None]
    img[..., :3] = img[..., :3] * (1 - w) + out * w
    Image.fromarray(np.round(img * 255).astype(np.uint8)).save(dst)


def main():
    base_name, primary, out = sys.argv[1], sys.argv[2].lstrip("#"), sys.argv[3]
    target = tuple(int(primary[i:i + 2], 16) / 255 for i in (0, 2, 4))
    base_dir = find_theme(base_name)
    base = dominant_colour(os.path.join(base_dir, "48x48/places/folder.png"))

    tmp = out + ".tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)

    for root, _, files in os.walk(base_dir):
        rel = os.path.relpath(root, base_dir)
        for f in files:
            if FOLDER_ICON.match(f):
                os.makedirs(os.path.join(tmp, rel), exist_ok=True)
                recolour(os.path.join(root, f), os.path.join(tmp, rel, f),
                         base, target)

    with open(os.path.join(base_dir, "index.theme")) as fh:
        index = fh.read()
    inherits = re.search(r"^Inherits=(.*)$", index, re.M)
    parents = ",".join(filter(None, [
        base_name, inherits.group(1) if inherits else "hicolor"]))
    index = re.sub(r"^Name=.*$", f"Name={os.path.basename(out)}", index,
                   count=1, flags=re.M)
    index = re.sub(r"^Inherits=.*$", "", index, flags=re.M)
    index = index.replace("[Icon Theme]", f"[Icon Theme]\nInherits={parents}",
                          1)
    with open(os.path.join(tmp, "index.theme"), "w") as fh:
        fh.write(index)

    subprocess.run(["gtk-update-icon-cache", "-qf", tmp], check=False)
    shutil.rmtree(out, ignore_errors=True)
    os.replace(tmp, out)
    print(f"{base_name}: folder #{bytes(round(c * 255) for c in base).hex()}"
          f" -> #{primary} in {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
