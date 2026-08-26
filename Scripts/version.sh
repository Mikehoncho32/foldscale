#!/usr/bin/env bash
# Prints the app version from project.yml — the single source of truth.
#   Scripts/version.sh          → 1.2.0   (MARKETING_VERSION)
#   Scripts/version.sh --build  → 3       (CURRENT_PROJECT_VERSION, what Sparkle compares)
set -euo pipefail
key=MARKETING_VERSION
[ "${1:-}" = "--build" ] && key=CURRENT_PROJECT_VERSION
sed -n "s/^ *${key}: *\"\([^\"]*\)\".*/\1/p" "$(dirname "$0")/../project.yml" | head -1
