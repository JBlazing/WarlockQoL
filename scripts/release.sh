#!/usr/bin/env bash
# Cut a release: set "## Version:" in the TOC, commit it, and create the annotated tag the
# CI pipeline publishes to CurseForge (see .gitlab-ci.yml).
#
# Usage: scripts/release.sh [patch|minor|major|X.Y.Z] [--alpha|--beta] [options]
#
#   patch|minor|major  Bump the TOC version. X.Y.Z sets it outright.
#                      Leave it out to tag the current TOC version (e.g. the next beta of
#                      a version you already bumped, or the final release after betas).
#   --alpha, --beta    Pre-release tag: vX.Y.Z-beta.N, N counts up from existing tags.
#   -m, --message MSG  Tag message (CurseForge changelog). Without it, an editor opens
#                      pre-filled with the commits since the previous tag.
#   --push             Push the commit and tag without asking.
#   --no-push          Don't push (prints the command to run later).
#   -y, --yes          Don't ask for confirmation.
#   -n, --dry-run      Show what would happen, change nothing.
#
# Examples:
#   scripts/release.sh patch --beta      2.4.0 -> 2.4.1, tag v2.4.1-beta.1
#   scripts/release.sh --beta            tag v2.4.1-beta.2 (no version change)
#   scripts/release.sh                   tag v2.4.1 (final)
#   scripts/release.sh minor -m "New demon bar"   2.4.1 -> 2.5.0, tag v2.5.0
set -euo pipefail

ADDON_DIR="${ADDON_DIR:-WarlockQoL}"
REMOTE="${REMOTE:-origin}"

die() { echo "ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit "${1:-0}"; }

bump="" pre="" message="" push="" yes=0 dry=0
while (($#)); do
  case "$1" in
    patch|minor|major) bump="$1" ;;
    [0-9]*.[0-9]*.[0-9]*) [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "bad version '$1'"; bump="$1" ;;
    --alpha) pre=alpha ;;
    --beta) pre=beta ;;
    -m|--message) (($# > 1)) || die "$1 needs a value"; message="$2"; shift ;;
    --push) push=1 ;;
    --no-push) push=0 ;;
    -y|--yes) yes=1 ;;
    -n|--dry-run) dry=1 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
  shift
done

cd "$(git rev-parse --show-toplevel)"
TOC="$ADDON_DIR/$ADDON_DIR.toc"
[[ -f "$TOC" ]] || die "$TOC not found"

confirm() {
  ((yes)) && return 0
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy] ]]
}

# --- Preconditions ---
if [[ -n "$(git status --porcelain)" ]]; then
  git status --short
  die "working tree has uncommitted changes; commit or stash them first."
fi
branch="$(git symbolic-ref --short -q HEAD || true)"
[[ -n "$branch" ]] || die "HEAD is detached; check out a branch first."
if [[ "$branch" != "main" ]]; then
  echo "Warning: you are on '$branch', not 'main'."
  confirm "Release from '$branch' anyway?" || exit 1
fi

echo "Fetching tags from $REMOTE..."
git fetch --quiet --tags "$REMOTE" || echo "Warning: could not fetch from $REMOTE; using local tags only."
if upstream="$(git rev-parse -q --verify '@{u}' 2>/dev/null)"; then
  [[ -z "$(git rev-list HEAD..'@{u}')" ]] || die "'$branch' is behind its upstream; pull first."
fi

# --- Versions ---
current="$(grep -m1 '^## Version:' "$TOC" | sed 's/^## Version:[[:space:]]*//; s/\r$//')"
[[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "TOC version '$current' is not X.Y.Z"
major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"

case "$bump" in
  "")    version="$current" ;;
  patch) version="$major.$minor.$((patch + 1))" ;;
  minor) version="$major.$((minor + 1)).0" ;;
  major) version="$((major + 1)).0.0" ;;
  *)     version="$bump" ;;
esac

git rev-parse -q --verify "refs/tags/v$version" >/dev/null \
  && die "v$version is already released. Pass patch, minor, major or X.Y.Z to bump the version."

if [[ -n "$pre" ]]; then
  last="$(git tag -l "v$version-$pre.*" | sed "s/^v$version-$pre\.//" | grep -E '^[0-9]+$' | sort -n | tail -1 || true)"
  tag="v$version-$pre.$(( ${last:-0} + 1 ))"
  type="$pre"
else
  tag="v$version"
  type="release"
fi
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag already exists."

# --- Default changelog: commits since the previous tag (a final release skips past
#     pre-release tags so it lists everything since the last final release) ---
if [[ -n "$pre" ]]; then
  prev_tag="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
else
  prev_tag="$(git describe --tags --abbrev=0 --match 'v*' --exclude '*-alpha*' --exclude '*-beta*' 2>/dev/null || true)"
fi
if [[ -z "$message" ]]; then
  changes="$(git log --no-merges --format='- %s' ${prev_tag:+"$prev_tag"..HEAD} | grep -v '^- Release v' || true)"
  default_message="${changes:-No changes listed.}"
fi

echo
echo "  TOC version : $current${bump:+ -> $version}"
echo "  Tag         : $tag ($type on CurseForge)"
echo "  Since       : ${prev_tag:-<first release>}"
echo "  Branch      : $branch"
if [[ -n "$message" ]]; then
  echo "  Message     : $message"
else
  echo "  Changelog   :"; sed 's/^/                /' <<<"$default_message"
fi
echo

if ((dry)); then
  echo "Dry run: nothing changed."
  exit 0
fi
confirm "Create $tag?" || { echo "Aborted."; exit 1; }

# --- Bump the TOC (keeps the file's line endings) ---
if [[ "$version" != "$current" ]]; then
  tmp="$(mktemp)"
  awk -v v="$version" '
    !done && /^## Version:/ { cr = /\r$/ ? "\r" : ""; print "## Version: " v cr; done = 1; next }
    { print }' "$TOC" > "$tmp"
  cat "$tmp" > "$TOC" && rm -f "$tmp"
  git add "$TOC"
  git commit --quiet -m "Release v$version"
  echo "Committed version bump: $(git log -1 --format='%h %s')"
fi

# --- Tag ---
if [[ -n "$message" ]]; then
  git tag -a "$tag" -m "$message"
elif ((yes)) || [[ ! -t 0 ]]; then
  git tag -a "$tag" -m "$default_message"
else
  echo "Opening editor for the tag message (it becomes the CurseForge changelog)..."
  git tag -a "$tag" -e -m "$default_message"
fi
echo "Created tag $tag."

# --- Push ---
push_cmd=(git push --atomic "$REMOTE" "$branch" "$tag")
if [[ -z "$push" ]]; then
  confirm "Push $branch and $tag to $REMOTE now (starts the CurseForge upload)?" && push=1 || push=0
fi
if ((push)); then
  "${push_cmd[@]}"
  echo "Pushed. The pipeline will publish $tag to CurseForge."
else
  echo "Not pushed. When ready, run:"
  echo "  ${push_cmd[*]}"
  echo "To undo instead:  git tag -d $tag${bump:+ && git reset --hard HEAD~1}"
fi
