#!/usr/bin/env bash
# Renders the images of the petals plymouth theme into $1 (needs rsvg-convert, from librsvg).
# Called by nixos/modules/boot-animation.nix at build time, so no PNG lives in the repo.
# Colours: config/caelestia/schemes/petals, like the petals SDDM greeter.
set -euo pipefail
out=$1
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A cherry blossom petal in unit coordinates: base at (0,0), notched tip at (0,-1), ~1.2 wide.
petal='M0 0 C-0.55 -0.12 -0.66 -0.68 -0.2 -0.96 Q-0.09 -1.03 0 -0.88 Q0.09 -1.03 0.2 -0.96 C0.66 -0.68 0.55 -0.12 0 0Z'
vein='M0 -0.04 Q-0.035 -0.42 0 -0.74 Q0.035 -0.42 0 -0.04Z'

# grad <id> <base colour> <tip colour>: base to tip, in the petal's unit coordinates
grad() {
  echo "<linearGradient id='$1' gradientUnits='userSpaceOnUse' x1='0' y1='0' x2='0' y2='-1'>
    <stop offset='0' stop-color='$2'/><stop offset='1' stop-color='$3'/></linearGradient>"
}

# svg <file> <size> <defs> <body>
svg() {
  printf "<svg xmlns='http://www.w3.org/2000/svg' width='%s' height='%s' viewBox='0 0 %s %s'><defs>%s</defs>%s</svg>" \
    "$2" "$2" "$2" "$2" "$3" "$4" > "$tmp/$1.svg"
  rsvg-convert "$tmp/$1.svg" -o "$out/$1.png"
}

# --- The flower: 640px canvas, centre (320,320), one image per petal so they bloom one by one.
# The angles must match petal_angle() in petals.script (SVG rotate is clockwise on screen).
S=640
defs="$(grad inner '#FF7FB6' '#FFE3EE')$(grad outer '#B9608F' '#F2B8D2')"
for i in $(seq 0 9); do
  a=$((i * 36))
  svg "inner-$i" $S "$defs" "<g transform='translate(320 320) rotate($a) translate(0 -14) scale(78 172)'>
    <path d='$petal' fill='url(#inner)'/><path d='$vein' fill='#FFFFFF' fill-opacity='0.28'/></g>"
  a=$((i * 36 + 18))
  svg "outer-$i" $S "$defs" "<g transform='translate(320 320) rotate($a) translate(0 -20) scale(120 276)'>
    <path d='$petal' fill='url(#outer)' fill-opacity='0.92'/><path d='$vein' fill='#FFD9E8' fill-opacity='0.22'/></g>"
done

# Halo behind the flower and its heart (pistil + stamens)
svg glow $S "<radialGradient id='g'><stop offset='0' stop-color='#FFA8CF' stop-opacity='0.42'/>
  <stop offset='0.55' stop-color='#E8B4F0' stop-opacity='0.12'/><stop offset='1' stop-color='#E8B4F0' stop-opacity='0'/></radialGradient>" \
  "<circle cx='320' cy='320' r='320' fill='url(#g)'/>"
stamens=""
for i in $(seq 0 11); do
  stamens+="<g transform='translate(320 320) rotate($((i * 30 + 7)))'><path d='M0 -8 L0 -40' stroke='#FFE3EE' stroke-width='2.5' stroke-linecap='round'/>
    <circle cx='0' cy='-42' r='5.5' fill='#FFE8A8'/></g>"
done
svg core $S "<radialGradient id='c'><stop offset='0' stop-color='#FFF4F8'/><stop offset='1' stop-color='#E8B4F0'/></radialGradient>" \
  "$stamens<circle cx='320' cy='320' r='17' fill='url(#c)'/>"

# --- Falling petals: 3 colours x 16 frames of a tumbling petal (rotation + flattening), 96px canvas.
F=16
n=0
for colour in '#FFA8CF:#FFE3EE' '#F2B8D2:#FFF0F6' '#E8B4F0:#F8E6FB'; do
  base=${colour%%:*} tip=${colour##*:}
  for f in $(seq 0 $((F - 1))); do
    a=$((f * 360 / F))
    # flattening of the petal seen edge on: |cos| of a second, slower axis
    sy=$(awk -v f="$f" -v F="$F" 'BEGIN { c = cos(f / F * 2 * 3.14159265); if (c < 0) c = -c; printf "%.3f", 0.35 + 0.65 * c }')
    svg "fall-$n-$f" 96 "$(grad p "$base" "$tip")" \
      "<g transform='translate(48 48) rotate($a) scale(1 $sy) translate(0 30) scale(36 60)'><path d='$petal' fill='url(#p)'/></g>"
  done
  n=$((n + 1))
done

# --- Password prompt (disk encryption): a pill and blossom bullets, drawn at 2x.
printf "<svg xmlns='http://www.w3.org/2000/svg' width='1200' height='144'><rect x='4' y='4' width='1192' height='136' rx='68'
  fill='#271E24' fill-opacity='0.85' stroke='#9F8A95' stroke-opacity='0.55' stroke-width='3'/></svg>" > "$tmp/entry.svg"
rsvg-convert "$tmp/entry.svg" -o "$out/entry.png"
blossom=""
for i in $(seq 0 4); do
  blossom+="<g transform='translate(40 40) rotate($((i * 72))) translate(0 -3) scale(20 34)'><path d='$petal' fill='url(#b)'/></g>"
done
svg bullet 80 "$(grad b '#FF8FC0' '#FFD9E8')" "$blossom<circle cx='40' cy='40' r='6' fill='#FFE8A8'/>"
