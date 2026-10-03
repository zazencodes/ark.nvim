#!/usr/bin/env bash
# Cuts a release from the [Unreleased] section of CHANGELOG.md.
#
# Usage: scripts/release.sh <patch|minor|X.Y.Z>
#   patch  fixes and additions
#   minor  breaking changes
#   X.Y.Z  explicit version (required for the first release)
#
# 1. Checks for a clean `main` that is in sync with origin
# 2. Renames [Unreleased] to [X.Y.Z] - YYYY-MM-DD, commits "Release vX.Y.Z", tags vX.Y.Z
# 3. Adds a fresh [Unreleased] section, commits "Add [Unreleased] section for next cycle"
# 4. Pushes main and the tag, then creates the GitHub release with the section as notes
set -euo pipefail
cd "$(dirname "$0")/.."

die() {
  echo "error: $*" >&2
  exit 1
}

bump=${1:-}
[[ $bump =~ ^(patch|minor|[0-9]+\.[0-9]+\.[0-9]+)$ ]] || die "usage: scripts/release.sh <patch|minor|X.Y.Z>"

[[ $(git branch --show-current) == main ]] || die "not on main"
[[ -z $(git status --porcelain) ]] || die "working tree is not clean"
git fetch --quiet origin main
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || die "main is not in sync with origin/main"

last=$(git tag --list 'v*' --sort=-version:refname | head -n1)
last=${last#v}
case $bump in
  patch | minor)
    [[ -n $last ]] || die "no previous release tag; pass an explicit version"
    IFS=. read -r major minor patch <<<"$last"
    if [[ $bump == patch ]]; then
      version="$major.$minor.$((patch + 1))"
    else
      version="$major.$((minor + 1)).0"
    fi
    ;;
  *)
    version=$bump
    if [[ -n $last ]]; then
      [[ $version != "$last" && $(printf '%s\n%s\n' "$last" "$version" | sort -V | tail -n1) == "$version" ]] ||
        die "version $version must be greater than the latest release $last"
    fi
    ;;
esac
tag="v$version"

notes=$(awk '/^## \[Unreleased\]$/ { found = 1; next } /^## \[/ { found = 0 } found' CHANGELOG.md)
[[ -n $(tr -d '[:space:]' <<<"$notes") ]] || die "CHANGELOG.md has no entries under ## [Unreleased]"

echo "Releasing $tag"
sed -i.bak "s/^## \[Unreleased\]$/## [$version] - $(date +%Y-%m-%d)/" CHANGELOG.md
rm CHANGELOG.md.bak
git add CHANGELOG.md
git commit --quiet -m "Release $tag"
git tag -a "$tag" -m "$tag"

awk 'NR == 1 { print; print ""; print "## [Unreleased]"; next } 1' CHANGELOG.md >CHANGELOG.md.tmp
mv CHANGELOG.md.tmp CHANGELOG.md
git add CHANGELOG.md
git commit --quiet -m "Add [Unreleased] section for next cycle"

git push --quiet origin main "$tag"
gh release create "$tag" --title "$tag" --notes "$notes"
