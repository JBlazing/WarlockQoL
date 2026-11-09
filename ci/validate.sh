#!/usr/bin/env bash
# Checks run on every pipeline: Lua syntax, TOC file list, and (on tags) the version.
set -euo pipefail

ADDON_DIR="${ADDON_DIR:-WarlockQoL}"
TOC="$ADDON_DIR/$ADDON_DIR.toc"
fail=0

[[ -f "$TOC" ]] || { echo "ERROR: $TOC not found"; exit 1; }

echo "== Lua 5.1 syntax check =="
while IFS= read -r -d '' f; do
  if ! luac5.1 -p "$f"; then
    fail=1
  fi
done < <(find "$ADDON_DIR" -name '*.lua' -print0)

echo "== TOC file list =="
# Every non-comment, non-blank line in the TOC is a file the game will load.
while IFS= read -r line; do
  line="${line%$'\r'}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  path="$ADDON_DIR/$(printf '%s' "$line" | sed 's#\\#/#g')"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: TOC lists '$line' but $path does not exist"
    fail=1
  fi
done < "$TOC"

toc_version="$(grep -m1 '^## Version:' "$TOC" | sed 's/^## Version:[[:space:]]*//; s/\r$//')"
echo "TOC version: ${toc_version:-<missing>}"
[[ -n "$toc_version" ]] || { echo "ERROR: no '## Version:' line in $TOC"; fail=1; }

if [[ -n "${CI_COMMIT_TAG:-}" ]]; then
  echo "== Tag check =="
  tag_version="${CI_COMMIT_TAG#v}"
  tag_version="${tag_version%%-*}" # drop -beta.1 / -alpha.1
  if [[ "$tag_version" != "$toc_version" ]]; then
    echo "ERROR: tag $CI_COMMIT_TAG does not match TOC version $toc_version."
    echo "       Update '## Version:' in $TOC, commit, and re-tag."
    fail=1
  fi
fi

if (( fail )); then
  echo "Validation failed."
  exit 1
fi
echo "All checks passed."
