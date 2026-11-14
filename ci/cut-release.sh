#!/usr/bin/env bash
# CI side of a manual release (the "release" job in .gitlab-ci.yml). Runs scripts/release.sh
# on the tip of the default branch, then pushes:
#   1. the version-bump commit, with ci.skip so it doesn't start a pipeline of its own;
#   2. the tag, which starts the tag pipeline that publishes to CurseForge.
#
# Inputs (set from the pipeline inputs by .gitlab-ci.yml):
#   RELEASE_BUMP     patch | minor | major | none
#   RELEASE_CHANNEL  prod | beta | alpha
#   RELEASE_MESSAGE  tag message / changelog; empty = commits since the previous tag
# Needs RELEASE_TOKEN: a project access token with write_repository, allowed to push to the
# default branch and create tags. (Pushes made with CI_JOB_TOKEN don't start pipelines, so the
# tag would never be published.)
set -euo pipefail

: "${RELEASE_TOKEN:?Set the RELEASE_TOKEN CI/CD variable (project access token, write_repository).}"
branch="$CI_DEFAULT_BRANCH"

args=()
case "${RELEASE_BUMP:-none}" in
  patch|minor|major) args+=("$RELEASE_BUMP") ;;
  none) ;;
  *) echo "ERROR: bad bump '$RELEASE_BUMP'"; exit 1 ;;
esac
case "${RELEASE_CHANNEL:-prod}" in
  prod) ;;
  beta|alpha) args+=("--$RELEASE_CHANNEL") ;;
  *) echo "ERROR: bad channel '$RELEASE_CHANNEL'"; exit 1 ;;
esac
[[ -n "${RELEASE_MESSAGE:-}" ]] && args+=(-m "$RELEASE_MESSAGE")

# Release exactly what this pipeline validated: refuse if the branch moved on since.
git fetch --quiet origin "$branch"
if [[ "$(git rev-parse "origin/$branch")" != "$CI_COMMIT_SHA" ]]; then
  echo "ERROR: $branch has moved since this pipeline started; run the release pipeline again."
  exit 1
fi
git checkout -q -B "$branch" "origin/$branch"

git config user.name "${GITLAB_USER_NAME:-Release bot}"
git config user.email "${GITLAB_USER_EMAIL:-noreply@${CI_SERVER_HOST}}"

git fetch --quiet --tags origin
tags_before="$(git tag | sort)"
bash scripts/release.sh "${args[@]}" --yes --no-push
tag="$(comm -13 <(echo "$tags_before") <(git tag | sort) | head -1)"
[[ -n "$tag" ]] || { echo "ERROR: release.sh didn't create a tag"; exit 1; }

push_url="${RELEASE_PUSH_URL:-https://oauth2:${RELEASE_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git}"
if [[ "$(git rev-parse HEAD)" != "$CI_COMMIT_SHA" ]]; then
  git push -o ci.skip "$push_url" "HEAD:refs/heads/$branch"
fi
git push "$push_url" "refs/tags/$tag"
echo "Released $tag. The tag pipeline will publish it to CurseForge:"
echo "  $CI_PROJECT_URL/-/pipelines?ref=$tag"
