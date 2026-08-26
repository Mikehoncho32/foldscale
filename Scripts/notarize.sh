#!/usr/bin/env bash
#
# Notarizes and staples a Radix DMG. This is the ONE step that needs an Apple
# Developer account — a paid membership with a "Developer ID Application"
# certificate. Until this is run, downloads open via right-click → Open (Gatekeeper).
#
#   ./Scripts/notarize.sh dist/Radix-1.1.0.dmg
#
# Prefer the one-shot pipeline: NOTARY_PROFILE=radix-notary CODE_SIGN_IDENTITY=... \
#   Scripts/build-dmg.sh <version>   (notarizes and staples both the app and the DMG)
#
# Prerequisites:
#   1. Rebuild the app signed with your Developer ID and hardened runtime:
#        CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#          Scripts/build-dmg.sh 1.0.0
#      (add ENABLE_HARDENED_RUNTIME=YES to the xcodebuild invocation in build-dmg.sh)
#   2. Store notary credentials once:
#        xcrun notarytool store-credentials radix-notary \
#          --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#      then run this with NOTARY_PROFILE=radix-notary.
set -euo pipefail

dmg="${1:?usage: notarize.sh <dmg>}"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
else
    xcrun notarytool submit "$dmg" \
        --apple-id "${APPLE_ID:?set APPLE_ID or NOTARY_PROFILE}" \
        --team-id "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}" \
        --password "${APPLE_APP_PASSWORD:?set APPLE_APP_PASSWORD}" \
        --wait
fi

xcrun stapler staple "$dmg"
echo "Notarized and stapled $dmg"
