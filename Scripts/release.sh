#!/usr/bin/env bash
# Cuts a release end to end, in the order that keeps the update feed safe:
#
#   Scripts/release.sh 1.3.0 [--from STEP]
#
#   preflight → branch → bump → build → draft-release → appcast → pr → publish → pages → homebrew
#
# Every step is idempotent, so a failed run (typically notarization) is fixed and re-run;
# --from skips ahead. Requires: CODE_SIGN_IDENTITY, NOTARY_PROFILE (default radix-notary),
# gh (logged in), xcodegen, xmllint, and a non-empty "## [Unreleased]" in CHANGELOG.md.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export NOTARY_PROFILE="${NOTARY_PROFILE:-radix-notary}"

version="${1:?usage: release.sh <version> [--from STEP]}"
from="preflight"
[ "${2:-}" = "--from" ] && from="${3:?--from needs a step}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "not a version: $version" >&2; exit 1; }
tag="v$version"
branch="release/$version"
dmg="dist/Foldscale-$version.dmg"
steps=(preflight branch bump build draft-release appcast pr publish pages homebrew summary)

say() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

preflight() {
    [ -n "${CODE_SIGN_IDENTITY:-}" ] || { echo "CODE_SIGN_IDENTITY is required (a release must be signed)" >&2; exit 1; }
    for tool in gh xcodegen xmllint; do command -v "$tool" >/dev/null || { echo "$tool not installed" >&2; exit 1; }; done
    gh auth status >/dev/null
    security find-identity -v -p codesigning | grep -q "Developer ID Application" || { echo "no Developer ID identity" >&2; exit 1; }
    [ "$(git branch --show-current)" = main ] || [ "$(git branch --show-current)" = "$branch" ] || { echo "run from main" >&2; exit 1; }
    [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "working tree not clean" >&2; exit 1; }
    git fetch -q --tags origin
    [ -z "$(git tag -l "$tag")" ] && [ -z "$(git ls-remote --tags origin "$tag")" ] || { echo "$tag already exists" >&2; exit 1; }
    Scripts/changelog-section.sh Unreleased >/dev/null || { echo "write the release notes under [Unreleased] first" >&2; exit 1; }
}

branch() {
    if [ "$(git branch --show-current)" != "$branch" ]; then
        git pull -q --ff-only origin main
        git switch -q -c "$branch" 2>/dev/null || git switch -q "$branch"
    fi
}

bump() {
    Scripts/set-version.sh "$version"
    if ! grep -q "^## \[$version\]" CHANGELOG.md; then
        today="$(date +%F)"
        perl -0pi -e "s/^## \[Unreleased\]\n/## [Unreleased]\n\n## [$version] - $today\n/m" CHANGELOG.md
        perl -pi -e "s{^\[Unreleased\]: .*}{[Unreleased]: https://github.com/Mikehoncho32/foldscale/compare/$tag...HEAD\n[$version]: https://github.com/Mikehoncho32/foldscale/releases/tag/$tag}" CHANGELOG.md
    fi
    Scripts/changelog-section.sh "$version" >/dev/null
}

build() {
    Scripts/build-dmg.sh "$version"
    [ -f "$dmg" ]
}

draft_release() {
    [ -f "$dmg" ] || { echo "$dmg missing — run --from build" >&2; exit 1; }
    notes="$(mktemp)"; Scripts/changelog-section.sh "$version" > "$notes"
    if gh release view "$tag" >/dev/null 2>&1; then
        gh release upload "$tag" "$dmg" --clobber
        gh release edit "$tag" --draft --notes-file "$notes"
    else
        gh release create "$tag" --draft --title "Foldscale $version" --notes-file "$notes" "$dmg"
    fi
}

appcast() {
    Scripts/appcast.sh "$version" "$dmg" --force
    Scripts/check-version.sh
}

pr() {
    git add project.yml site/index.html site/appcast.xml CHANGELOG.md
    git diff --cached --quiet || git commit -q -m "chore(release): $version"
    git push -q -u origin "$branch"
    tree_before="$(git rev-parse 'HEAD^{tree}')"
    if ! gh pr view "$branch" >/dev/null 2>&1; then
        gh pr create --title "chore(release): $version" --body "$(Scripts/changelog-section.sh "$version")"
    fi
    for _ in $(seq 1 24); do [ "$(gh pr checks "$branch" 2>/dev/null | wc -l | tr -d ' ')" -ge 3 ] && break; sleep 10; done
    gh pr checks "$branch" --watch --fail-fast
    gh pr merge "$branch" --squash
    for _ in $(seq 1 30); do [ "$(gh pr view "$branch" --json state -q .state)" = MERGED ] && break; sleep 5; done
    git switch -q main && git pull -q --ff-only origin main
    git push -q origin --delete "$branch" 2>/dev/null || true
    git branch -q -D "$branch" 2>/dev/null || true
    [ "$(git rev-parse 'HEAD^{tree}')" = "$tree_before" ] || {
        echo "main's tree differs from what was built (rebased?) — rerun from build" >&2; exit 1; }
}

publish() {
    gh release edit "$tag" --draft=false --target "$(git rev-parse HEAD)"
    git fetch -q --tags origin
    git tag --points-at HEAD | grep -qx "$tag" || { echo "$tag does not point at HEAD" >&2; exit 1; }
    url="https://github.com/Mikehoncho32/foldscale/releases/download/$tag/Foldscale-$version.dmg"
    for _ in $(seq 1 12); do curl -fsIL -o /dev/null "$url" && break; sleep 5; done
    curl -fsIL -o /dev/null "$url"
}

pages() {
    run_id=""
    for _ in $(seq 1 12); do
        run_id="$(gh run list --workflow pages.yml --branch main --limit 1 --json databaseId -q '.[0].databaseId')"
        [ -n "$run_id" ] && break; sleep 5
    done
    [ -n "$run_id" ] && gh run watch "$run_id" --exit-status
    for _ in $(seq 1 20); do
        if curl -fsSL https://foldscale.com/appcast.xml | grep -q "<sparkle:shortVersionString>$version<"; then return 0; fi
        sleep 30
    done
    echo "foldscale.com/appcast.xml does not show $version yet (CDN cache?) — check again in a few minutes" >&2
}

homebrew() {
    tmp="$(mktemp -d)"
    gh repo clone Mikehoncho32/homebrew-foldscale "$tmp" -- -q
    (cd "$tmp" && ./update.sh "$version" && git commit -qam "foldscale $version" && git push -q)
    rm -rf "$tmp"
}

summary() {
    echo
    echo "Released Foldscale $version"
    echo "  tag:      $tag"
    echo "  dmg:      $dmg  $(shasum -a 256 "$dmg" 2>/dev/null | cut -d' ' -f1)"
    echo "  feed:     https://foldscale.com/appcast.xml"
    echo "  homebrew: brew install --cask mikehoncho32/foldscale/foldscale"
}

started=0
for step in "${steps[@]}"; do
    [ "$step" = "$from" ] && started=1
    [ "$started" = 1 ] || continue
    say "$step"
    "${step//-/_}"
done
