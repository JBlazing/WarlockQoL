#!/usr/bin/env bash
# Publishes the tag pipeline's build as a GitHub release (the "github" job in .gitlab-ci.yml):
#   1. pushes the tag (and the commits it needs) to the GitHub repo;
#   2. creates the GitHub release for it, or reuses it if a previous run made it;
#   3. attaches dist/<zip>, replacing an asset of the same name.
# Safe to retry.
#
# Variables (Settings > CI/CD > Variables):
#   GITHUB_REPO    owner/name of the GitHub repo, e.g. someone/WarlockQoL. The job only runs
#                  when this is set.
#   GITHUB_TOKEN   GitHub fine-grained token for that repo with "Contents: Read and write"
#                  (masked + protected).
#   GH_DRY_RUN=1   Show what would happen, push and create nothing.
set -euo pipefail

API="https://api.github.com"
UPLOADS="https://uploads.github.com"
ADDON_DIR="${ADDON_DIR:-WarlockQoL}"

: "${GITHUB_REPO:?Set GITHUB_REPO (owner/name) in Settings > CI/CD > Variables}"
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN in Settings > CI/CD > Variables}"
: "${CI_COMMIT_TAG:?This job only runs in tag pipelines}"
[[ "$GITHUB_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: GITHUB_REPO '$GITHUB_REPO' is not owner/name"; exit 1; }

tag="$CI_COMMIT_TAG"
zip_name="$(cat dist/ZIP_NAME)"
version="$(cat dist/VERSION)"
zip_path="dist/$zip_name"
[[ -f "$zip_path" ]] || { echo "ERROR: $zip_path missing; did the package job run?"; exit 1; }

case "$tag" in
  *-alpha*|*-beta*) prerelease=true  make_latest=false ;;
  *)                prerelease=false make_latest=true ;;
esac

body="$(bash "$(dirname "$0")/changelog.sh")"
echo "Release : $ADDON_DIR $version ($tag) on github.com/$GITHUB_REPO"
echo "Pre-release: $prerelease"
echo "---- notes ----"; echo "$body"; echo "---------------"

if [[ "${GH_DRY_RUN:-0}" == "1" ]]; then
  echo "GH_DRY_RUN=1, nothing pushed or created."
  exit 0
fi

# gh_api METHOD URL [curl args...]: response body goes to $GH_OUT, status to $GH_STATUS.
# Fails on HTTP >= 400 unless GH_ALLOW is set to that status. (Not meant for $(...):
# GH_STATUS would be lost in the subshell.)
GH_OUT="$(mktemp)"
trap 'rm -f "$GH_OUT"' EXIT
gh_api() {
  local method="$1" url="$2"; shift 2
  GH_STATUS="$(curl -sS -o "$GH_OUT" -w '%{http_code}' -X "$method" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@" "$url")"
  if (( GH_STATUS >= 400 )) && [[ "$GH_STATUS" != "${GH_ALLOW:-}" ]]; then
    echo "ERROR: $method $url returned HTTP $GH_STATUS:" >&2
    cat "$GH_OUT" >&2; echo >&2
    exit 1
  fi
}

# --- 1. Tag on GitHub (pushing a tag brings the commits it points at) ---
echo "Pushing $tag to GitHub..."
git -c credential.helper= push --quiet \
  "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" "refs/tags/$tag"

# --- 2. Release (reuse it if a previous run already created it) ---
payload="$(jq -cn --arg tag "$tag" --arg name "$ADDON_DIR $version" --arg body "$body" \
  --argjson pre "$prerelease" --arg latest "$make_latest" \
  '{tag_name: $tag, name: $name, body: $body, prerelease: $pre, make_latest: $latest}')"
GH_ALLOW=404 gh_api GET "$API/repos/$GITHUB_REPO/releases/tags/$tag"
if [[ "$GH_STATUS" == "404" ]]; then
  gh_api POST "$API/repos/$GITHUB_REPO/releases" --data "$payload"
  echo "Created release."
else
  id="$(jq -r '.id' "$GH_OUT")"
  gh_api PATCH "$API/repos/$GITHUB_REPO/releases/$id" --data "$payload"
  echo "Release already existed; updated it."
fi
release_id="$(jq -r '.id' "$GH_OUT")"
release_url="$(jq -r '.html_url' "$GH_OUT")"
old_asset="$(jq -r --arg n "$zip_name" '.assets[]? | select(.name == $n) | .id' "$GH_OUT")"

# --- 3. Zip asset (replace one left by an earlier run) ---
if [[ -n "$old_asset" ]]; then
  gh_api DELETE "$API/repos/$GITHUB_REPO/releases/assets/$old_asset"
  echo "Removed the old $zip_name asset."
fi
gh_api POST "$UPLOADS/repos/$GITHUB_REPO/releases/$release_id/assets?name=$zip_name" \
  -H "Content-Type: application/zip" --data-binary "@$zip_path"
echo "Uploaded $zip_name."
echo "GitHub release: $release_url"
