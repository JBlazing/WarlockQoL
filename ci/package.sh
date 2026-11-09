#!/usr/bin/env bash
# Builds dist/<Addon>-<version>.zip with the addon folder at the top level,
# which is the layout CurseForge and the game expect.
set -euo pipefail

ADDON_DIR="${ADDON_DIR:-WarlockQoL}"
TOC="$ADDON_DIR/$ADDON_DIR.toc"

if [[ -n "${CI_COMMIT_TAG:-}" ]]; then
  version="${CI_COMMIT_TAG#v}"
else
  toc_version="$(grep -m1 '^## Version:' "$TOC" | sed 's/^## Version:[[:space:]]*//; s/\r$//')"
  version="${toc_version}-dev.${CI_COMMIT_SHORT_SHA:-local}"
fi

stage_dir="$(mktemp -d)"
trap 'rm -rf "$stage_dir"' EXIT

cp -R "$ADDON_DIR" "$stage_dir/$ADDON_DIR"
[[ -f LICENSE ]] && cp LICENSE "$stage_dir/$ADDON_DIR/LICENSE"

# Strip anything that shouldn't ship to players.
find "$stage_dir" \( -name '.*' -o -name '*.bak' -o -name '*.orig' -o -name '*.tmp' \) \
  -not -path "$stage_dir" -exec rm -rf {} + 2>/dev/null || true

mkdir -p dist
zip_name="${ADDON_DIR}-${version}.zip"
(cd "$stage_dir" && zip -rq9 "$OLDPWD/dist/$zip_name" "$ADDON_DIR")

echo "$version"  > dist/VERSION
echo "$zip_name" > dist/ZIP_NAME

echo "Built dist/$zip_name"
unzip -l "dist/$zip_name"
