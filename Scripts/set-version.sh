#!/usr/bin/env bash
# The only place versions change: project.yml (MARKETING_VERSION, and CURRENT_PROJECT_VERSION
# +1 — Sparkle compares the build number, so it must strictly increase) plus the static
# fallbacks in site/index.html. Idempotent.
#   Scripts/set-version.sh 1.3.0
set -euo pipefail
cd "$(dirname "$0")/.."
new="${1:?usage: set-version.sh <version>}"
[[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "not a version: $new" >&2; exit 1; }
current="$(Scripts/version.sh)"
build="$(Scripts/version.sh --build)"
if [ "$current" != "$new" ]; then
    build=$((build + 1))
    sed -i '' -E \
        -e "s/^( *MARKETING_VERSION: *)\"[^\"]*\"/\1\"$new\"/" \
        -e "s/^( *CURRENT_PROJECT_VERSION: *)\"[^\"]*\"/\1\"$build\"/" project.yml
fi
sed -i '' -E \
    -e "s/Foldscale-[0-9]+\.[0-9]+\.[0-9]+\.dmg/Foldscale-$new.dmg/g" \
    -e "s/(id=\"version2?\">)[0-9]+\.[0-9]+\.[0-9]+/\1$new/g" site/index.html
echo "version $new (build $build)"
