# Releasing Warlock QoL

Releases are published to CurseForge by the GitLab pipeline whenever a version tag is pushed.
`scripts/release.sh` updates the addon's version and creates that tag for you.

## Quick start

Run from Git Bash in the repo:

```sh
bash scripts/release.sh patch --beta   # 2.4.0 -> 2.4.1, commit, tag v2.4.1-beta.1
bash scripts/release.sh --beta         # tag v2.4.1-beta.2 (no version change)
bash scripts/release.sh                # tag v2.4.1 (final release)
bash scripts/release.sh minor --alpha  # 2.4.1 -> 2.5.0, tag v2.5.0-alpha.1
bash scripts/release.sh 3.0.0 -m "Big rewrite"
```

Commit or stash your work first: the script won't run with uncommitted changes.

## Options

| Option | What it does |
| --- | --- |
| `patch` / `minor` / `major` | Raise the `## Version:` line in `WarlockQoL/WarlockQoL.toc` and commit it. |
| `X.Y.Z` | Set the version to exactly that. |
| *(no version)* | Tag the version already in the `.toc`. Use this for the next beta, or for the final release after betas. |
| `--alpha`, `--beta` | Make a pre-release tag (`vX.Y.Z-beta.N`). |
| `-m`, `--message MSG` | Tag message, used as the CurseForge changelog. |
| `--push` / `--no-push` | Push without asking, or don't push at all. |
| `-y`, `--yes` | Skip all confirmation questions. |
| `-n`, `--dry-run` | Show what would happen without changing anything. |
| `-h`, `--help` | Show usage. |

## How it works

1. **Checks first.** It stops if there are uncommitted changes, if your branch is behind the
   remote, or if the tag already exists. It warns if you're not on `main`. It fetches tags
   from the remote so it sees releases made elsewhere.
2. **Works out the version and tag.**
   - The `.toc` always holds a plain `X.Y.Z`. Alpha/beta only appears in the tag, which is
     what `ci/validate.sh` expects (it checks the tag's `X.Y.Z` against the `.toc`).
   - Alpha/beta numbers count up from the tags that already exist: `-beta.1`, `-beta.2`, …
   - With no version argument it refuses if that version is already released, so you can't
     accidentally re-release it.
3. **Shows a summary and asks to continue.** The summary lists the version change, the tag,
   the CurseForge release type and the changelog.
4. **Commits the version change** as `Release vX.Y.Z` (only if the version changed). The
   `.toc` keeps its existing line endings.
5. **Creates an annotated tag.** Its message becomes the CurseForge changelog. Without `-m`,
   an editor opens pre-filled with the commits since the previous tag:
   - a pre-release lists commits since the previous tag of any kind;
   - a final release lists everything since the last *final* release, so changes made during
     the betas are included.
6. **Pushes** the branch and tag together after asking (pushing starts the CurseForge upload).
   If you don't push, it prints the push command, plus the command to undo the tag and commit.

## Testing locally before a release

`scripts/install-local.sh` copies the addon into your WoW client, replacing the installed copy
(so files deleted in the repo are removed from the game too):

```sh
bash scripts/install-local.sh                         # the _forever_ client (default)
bash scripts/install-local.sh anniversary classic_era # other clients
bash scripts/install-local.sh all                     # every client
bash scripts/install-local.sh -n                      # dry run
```

The WoW folder defaults to `D:/Games/World of Warcraft`; set `WOW_DIR` to use another.
Type `/reload` in game afterwards, or restart the game if you added new files.

## Tag → CurseForge release type

| Tag | Release type |
| --- | --- |
| `v2.4.1` | release |
| `v2.4.1-beta.1` | beta |
| `v2.4.1-alpha.1` | alpha |

## Typical flow

```sh
bash scripts/release.sh patch --beta   # first beta of the next version
# ...testers report a bug, fix it, commit...
bash scripts/release.sh --beta         # next beta, same version
bash scripts/release.sh                # final release
```

## What the pipeline does after the push

The tag starts the pipeline in `.gitlab-ci.yml`:

1. **lint** – Lua syntax check, every file listed in the `.toc` exists, tag matches `.toc` version.
2. **package** – zips the addon into `dist/`.
3. **curseforge** – uploads the zip with the tag message as the changelog.

It needs the `CF_API_TOKEN` and `CF_PROJECT_ID` CI/CD variables. Set `CF_DRY_RUN=1` to run
everything except the upload. Job images come through the Docker Hub cache on the Pi
(`HUB_MIRROR`, default `localhost:5001`).
