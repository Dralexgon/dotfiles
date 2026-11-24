#!/usr/bin/env bash
# Points horizon-launcher.json at the newest Horizon launcher release (tags `launcher@X.Y.Z`;
# GitHub's "latest" release is an old v0.2.97 tag, so it can't be used). Run by nixcfg's update
# before `nix flake update`; run it by hand otherwise.
set -euo pipefail
json="$(dirname "$(realpath "$0")")/horizon-launcher.json"
version=$(curl -fsSL 'https://api.github.com/repos/horizon-rust/horizon/releases?per_page=50' \
  | jq -r '[.[] | select(.tag_name | startswith("launcher@")) | select((.draft or .prerelease) | not)][0].tag_name // empty' \
  | sed 's/^launcher@//')
[ -n "$version" ] || { echo "horizon-launcher: no launcher release found" >&2; exit 1; }
current=$(jq -r .version "$json")
if [ "$version" = "$current" ]; then
  echo "horizon-launcher: $current is the newest release"
  exit 0
fi
url="https://github.com/horizon-rust/horizon/releases/download/launcher@$version/horizon-launcher-linux-x86_64.tar.gz"
hash=$(nix store prefetch-file --json "$url" | jq -r .hash)
jq -n --arg v "$version" --arg h "$hash" '{version: $v, hash: $h}' > "$json"
echo "horizon-launcher: $current -> $version"
