#!/usr/bin/env bash
# Copy the addon from this repo into a local WoW client's Interface/AddOns folder, replacing
# the installed copy so files deleted in the repo don't linger in the game.
# Run /reload in game afterwards (a new .toc entry or new file needs a full restart).
#
# Usage: scripts/install-local.sh [flavor...] [-n|--dry-run]
#
#   flavor   WoW client folder: forever (default), retail, classic, classic_era,
#            anniversary, ... (with or without the underscores), or "all" for every
#            client that has an Interface/AddOns folder.
#
# Environment:
#   WOW_DIR    WoW install folder (default: D:/Games/World of Warcraft).
#   ADDON_DIR  Addon folder in this repo (default: WarlockQoL).
#
# Examples:
#   scripts/install-local.sh
#   scripts/install-local.sh anniversary classic_era
#   WOW_DIR="C:/Program Files (x86)/World of Warcraft" scripts/install-local.sh retail
set -euo pipefail

WOW_DIR="${WOW_DIR:-D:/Games/World of Warcraft}"
ADDON_DIR="${ADDON_DIR:-WarlockQoL}"

die() { echo "ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit "${1:-0}"; }

flavors=() dry=0
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) dry=1 ;;
    -h|--help) usage ;;
    -*) echo "Unknown option: $arg" >&2; usage 1 ;;
    *) flavors+=("$arg") ;;
  esac
done
((${#flavors[@]})) || flavors=(forever)

command -v cygpath >/dev/null && WOW_DIR="$(cygpath -u "$WOW_DIR")"
[[ -d "$WOW_DIR" ]] || die "WoW folder not found: $WOW_DIR (set WOW_DIR)"

cd "$(git rev-parse --show-toplevel 2>/dev/null || dirname "$0")"
src="$ADDON_DIR"
[[ -f "$src/$ADDON_DIR.toc" ]] || die "$src/$ADDON_DIR.toc not found; run from the repo."

# Resolve flavors to AddOns folders.
targets=()
for f in "${flavors[@]}"; do
  if [[ "$f" == all ]]; then
    for d in "$WOW_DIR"/_*_/Interface/AddOns; do [[ -d "$d" ]] && targets+=("$d"); done
    continue
  fi
  f="${f#_}"; f="${f%_}"
  d="$WOW_DIR/_${f}_/Interface/AddOns"
  if [[ ! -d "$d" ]]; then
    echo "Available clients:" >&2
    for c in "$WOW_DIR"/_*_/Interface/AddOns; do [[ -d "$c" ]] && c="${c%/Interface/AddOns}" && echo "  ${c##*/_}" | sed 's/_$//' >&2; done
    die "no Interface/AddOns folder for '$f' in $WOW_DIR"
  fi
  targets+=("$d")
done
((${#targets[@]})) || die "no WoW clients with an Interface/AddOns folder in $WOW_DIR"

version="$(grep -m1 '^## Version:' "$src/$ADDON_DIR.toc" | sed 's/^## Version:[[:space:]]*//; s/\r$//')"
echo "Installing $ADDON_DIR $version"

for addons in "${targets[@]}"; do
  dest="$addons/$ADDON_DIR"
  client="${addons%/Interface/AddOns}"; client="${client##*/}"
  if ((dry)); then
    echo "  [dry run] $client: would replace $dest"
    continue
  fi
  # Copy to a temp folder next to the target, then swap, so a failed copy never leaves
  # a half-installed addon behind.
  tmp="$addons/.$ADDON_DIR.installing"
  rm -rf "$tmp"
  cp -R "$src" "$tmp"
  find "$tmp" -mindepth 1 \( -name '.*' -o -name '*.bak' -o -name '*.orig' -o -name '*.tmp' \) \
    -exec rm -rf {} + 2>/dev/null || true
  [[ -f LICENSE ]] && cp LICENSE "$tmp/LICENSE"
  rm -rf "$dest"
  mv "$tmp" "$dest"
  echo "  $client: $dest"
done
echo "Done. Type /reload in game (restart the game if you added new files)."
