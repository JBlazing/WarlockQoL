#!/usr/bin/env bash
# Prints the release notes for CI_COMMIT_TAG (or HEAD): the annotated tag's message, else the
# commits since the previous tag. Shared by the CurseForge and GitHub uploads.
set -euo pipefail

changelog=""
if [[ -n "${CI_COMMIT_TAG:-}" ]] && [[ "$(git cat-file -t "$CI_COMMIT_TAG" 2>/dev/null)" == "tag" ]]; then
  changelog="$(git tag -l --format='%(contents)' "$CI_COMMIT_TAG" | sed '/-----BEGIN PGP SIGNATURE-----/,$d')"
fi
if [[ -z "${changelog//[[:space:]]/}" ]]; then
  prev_tag="$(git describe --tags --abbrev=0 "${CI_COMMIT_TAG:-HEAD}^" 2>/dev/null || true)"
  range="${prev_tag:+$prev_tag..}${CI_COMMIT_TAG:-HEAD}"
  changelog="$(git log --no-merges --format='- %s' "$range")"
fi
printf '%s\n' "${changelog:-No changes listed.}"
