---
name: release
description: Prepare and publish an ark.nvim release. Use when asked to release, cut a version, tag, publish, or audit the changelog before a release.
---

# Releasing ark.nvim

Run commands from the repo root. A release is a `vX.Y.Z` git tag plus a GitHub release; lazy.nvim users on `version = "*"` pick it up from the tag. There is no package to publish.

**Versioning**: `patch` = fixes and additions, `minor` = breaking changes (renamed commands, keymaps, options or adapter fields). No major releases.

1. **Audit the changelog.** Find the last release with `git tag --sort=-version:refname | head -1` and list the commits since it with `git log <tag>..HEAD --oneline` (all commits if there is no tag). Skip changelog, docs-only and release housekeeping commits. For every other commit, check that `## [Unreleased]` in `CHANGELOG.md` has an entry, and add missing ones under the right subsection. Report what you added. If the changes break existing setups, the release must be `minor` and the entry goes under `### Breaking Changes` with what users need to change.

2. **Test end to end.** Follow the Testing section of `AGENTS.md`: on an isolated tmux server, run `:ArkEdit` against a fake agent and at least one real harness, and open `:ArkHarness`. Failures block the release unless the user accepts the risk.

3. **Get the user's go-ahead.** Show the `[Unreleased]` section and the version it will become, and wait for confirmation. The next step pushes and publishes.

4. **Run the release script** from a clean `main` that is in sync with `origin/main`:
   ```bash
   scripts/release.sh patch    # fixes and additions
   scripts/release.sh minor    # breaking changes
   scripts/release.sh 0.1.0    # explicit version, required for the first release
   ```
   It turns `## [Unreleased]` into `## [X.Y.Z] - YYYY-MM-DD`, commits `Release vX.Y.Z`, tags `vX.Y.Z`, adds a fresh `## [Unreleased]` section, commits `Add [Unreleased] section for next cycle`, pushes `main` and the tag, and runs `gh release create` with that version's changelog section as the notes.

5. **Verify** with `gh release view vX.Y.Z` and check that the README's release badge shows the new version.

**If it fails partway**: never rerun the script for a version whose tag was already pushed. If the push succeeded but `gh release create` failed, create the release by hand with that version's `CHANGELOG.md` section as `--notes`. If it failed before the push, delete the local tag (`git tag -d vX.Y.Z`), undo the local release commits with `git reset --keep origin/main`, and rerun.

## Changelog format

`CHANGELOG.md` follows the Pi convention. Subsections of `## [Unreleased]`, in order: `### Breaking Changes`, `### Added`, `### Changed`, `### Fixed`, `### Removed`. Entries are one line, in past tense, and say what changed for the user (`Added :ArkFoo, which ...`). Released sections are immutable.
