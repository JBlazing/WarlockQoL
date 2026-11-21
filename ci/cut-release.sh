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
# Needs push access to the default branch and tags, through one of (see RELEASING.md):
#   RELEASE_DEPLOY_KEY  private SSH key of a deploy key with write access (preferred). Either a
#                       File variable, or the key base64-encoded on one line so it can be masked.
#   RELEASE_TOKEN       personal/project access token with write_repository.
# (Pushes made with CI_JOB_TOKEN don't start pipelines, so the tag would never be published.)
# Optional: RELEASE_SSH_KNOWN_HOSTS, the GitLab host key line(s); otherwise fetched with
# ssh-keyscan.
set -euo pipefail

branch="$CI_DEFAULT_BRANCH"

# --- Where to push ---
if [[ -n "${RELEASE_DEPLOY_KEY:-}" ]]; then
  ssh_dir="$(mktemp -d)"
  trap 'rm -rf "$ssh_dir"' EXIT
  key="$ssh_dir/id"
  if [[ -f "$RELEASE_DEPLOY_KEY" ]]; then
    tr -d '\r' < "$RELEASE_DEPLOY_KEY" > "$key"        # File variable
  elif [[ "$RELEASE_DEPLOY_KEY" == -----BEGIN* ]]; then
    printf '%s' "$RELEASE_DEPLOY_KEY" | tr -d '\r' > "$key"
  else
    printf '%s' "$RELEASE_DEPLOY_KEY" | base64 -d > "$key" \
      || { echo "ERROR: RELEASE_DEPLOY_KEY is neither a key nor base64 of one."; exit 1; }
  fi
  echo >> "$key" # OpenSSH rejects a key without a final newline
  chmod 600 "$key"

  ssh_host="${CI_SERVER_SHELL_SSH_HOST:-$CI_SERVER_HOST}"
  ssh_port="${CI_SERVER_SHELL_SSH_PORT:-22}"
  if [[ -n "${RELEASE_SSH_KNOWN_HOSTS:-}" ]]; then
    printf '%s\n' "$RELEASE_SSH_KNOWN_HOSTS" > "$ssh_dir/known_hosts"
  else
    ssh-keyscan -p "$ssh_port" "$ssh_host" > "$ssh_dir/known_hosts" 2>/dev/null
    [[ -s "$ssh_dir/known_hosts" ]] || { echo "ERROR: ssh-keyscan $ssh_host failed."; exit 1; }
  fi
  export GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$ssh_dir/known_hosts"
  push_url="ssh://git@${ssh_host}:${ssh_port}/${CI_PROJECT_PATH}.git"
elif [[ -n "${RELEASE_TOKEN:-}" ]]; then
  push_url="https://oauth2:${RELEASE_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git"
else
  echo "ERROR: set the RELEASE_DEPLOY_KEY (deploy key with write access) or RELEASE_TOKEN"
  echo "       CI/CD variable so the job can push the release. See RELEASING.md."
  exit 1
fi
push_url="${RELEASE_PUSH_URL:-$push_url}"

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

if [[ "$(git rev-parse HEAD)" != "$CI_COMMIT_SHA" ]]; then
  git push -o ci.skip "$push_url" "HEAD:refs/heads/$branch"
fi
git push "$push_url" "refs/tags/$tag"
echo "Released $tag. The tag pipeline will publish it to CurseForge:"
echo "  $CI_PROJECT_URL/-/pipelines?ref=$tag"
