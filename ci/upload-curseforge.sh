#!/usr/bin/env bash
# Uploads dist/<zip> to CurseForge via the WoW upload API:
#   POST https://wow.curseforge.com/api/projects/{projectId}/upload-file
# Once uploaded and approved, the CurseForge app offers the update to users automatically.
set -euo pipefail

API="https://wow.curseforge.com/api"
ADDON_DIR="${ADDON_DIR:-WarlockQoL}"
TOC="$ADDON_DIR/$ADDON_DIR.toc"

: "${CF_API_TOKEN:?Set CF_API_TOKEN in Settings > CI/CD > Variables}"
: "${CF_PROJECT_ID:?Set CF_PROJECT_ID in Settings > CI/CD > Variables}"

zip_name="$(cat dist/ZIP_NAME)"
version="$(cat dist/VERSION)"
zip_path="dist/$zip_name"
[[ -f "$zip_path" ]] || { echo "ERROR: $zip_path missing; did the package job run?"; exit 1; }

# --- Release type from the tag suffix ---
case "${CI_COMMIT_TAG:-}" in
  *-alpha*) release_type="alpha" ;;
  *-beta*)  release_type="beta" ;;
  *)        release_type="release" ;;
esac

# --- Game versions ---
# Prefer explicit IDs. Otherwise turn "## Interface: 16001" into "1.60.1" and look it up.
if [[ -n "${CF_GAME_VERSION_IDS:-}" ]]; then
  game_versions="$(jq -cn --arg ids "$CF_GAME_VERSION_IDS" '$ids | split(",") | map(gsub("\\s";"") | tonumber)')"
else
  interface="$(grep -m1 '^## Interface:' "$TOC" | sed 's/^## Interface:[[:space:]]*//; s/\r$//' | cut -d, -f1)"
  major=$(( interface / 10000 ))
  minor=$(( (interface % 10000) / 100 ))
  patch=$(( interface % 100 ))
  game_name="${major}.${minor}.${patch}"
  echo "Looking up CurseForge game version '$game_name' (from Interface $interface)"

  all_versions="$(curl -fsS -H "X-Api-Token: $CF_API_TOKEN" "$API/game/versions")"
  game_versions="$(jq -c --arg n "$game_name" '[.[] | select(.name == $n) | .id]' <<<"$all_versions")"

  if [[ "$game_versions" == "[]" ]]; then
    echo "ERROR: CurseForge has no game version named '$game_name'."
    echo "Closest matches (id  name):"
    jq -r --arg p "${major}.${minor}" '.[] | select(.name | startswith($p)) | "  \(.id)  \(.name)"' <<<"$all_versions" | head -20
    echo "Set CF_GAME_VERSION_IDS to the right ID(s) and re-run this job."
    exit 1
  fi
fi
echo "Game version IDs: $game_versions"

# --- Changelog: annotated tag message, else commits since the previous tag ---
changelog="# ${ADDON_DIR} ${version}"$'\n\n'"$(bash "$(dirname "$0")/changelog.sh")"
echo "---- changelog ----"; echo "$changelog"; echo "-------------------"

metadata="$(jq -cn \
  --arg changelog "$changelog" \
  --arg displayName "${ADDON_DIR} ${version}" \
  --arg releaseType "$release_type" \
  --argjson gameVersions "$game_versions" \
  '{changelog: $changelog, changelogType: "markdown", displayName: $displayName,
    gameVersions: $gameVersions, releaseType: $releaseType}')"
echo "Metadata: $metadata"

if [[ "${CF_DRY_RUN:-0}" == "1" ]]; then
  echo "CF_DRY_RUN=1, skipping upload of $zip_path."
  exit 0
fi

echo "Uploading $zip_path to CurseForge project $CF_PROJECT_ID as $release_type..."
response_file="$(mktemp)"
http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
  -H "X-Api-Token: $CF_API_TOKEN" \
  --form-string "metadata=$metadata" \
  -F "file=@$zip_path" \
  "$API/projects/$CF_PROJECT_ID/upload-file")"

if [[ "$http_code" != "200" ]]; then
  echo "ERROR: CurseForge returned HTTP $http_code:"
  cat "$response_file"; echo
  exit 1
fi

file_id="$(jq -r '.id' "$response_file")"
echo "Uploaded. CurseForge file ID: $file_id"
