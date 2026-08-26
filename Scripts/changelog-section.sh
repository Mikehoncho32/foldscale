#!/usr/bin/env bash
# Prints the body of "## [<version>]" from CHANGELOG.md ("Unreleased" when no version given).
#   Scripts/changelog-section.sh 1.3.0
set -euo pipefail
cd "$(dirname "$0")/.."
v="${1:-Unreleased}"
body="$(awk -v v="$v" '
    $0 ~ "^## \\[" v "\\]" { keep = 1; next }
    /^## \[/ { keep = 0 }
    keep { print }' CHANGELOG.md | sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
if [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ]; then
    echo "CHANGELOG.md has nothing under [$v]" >&2
    exit 1
fi
printf '%s\n' "$body"
