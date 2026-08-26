#!/usr/bin/env bash
#
# Builds Radix in Release and packages it into a distributable DMG.
#
#   Scripts/build-dmg.sh [version]
#
# The app is ad-hoc signed unless a Developer ID is supplied via CODE_SIGN_IDENTITY.
# For a notarized release, set CODE_SIGN_IDENTITY to your "Developer ID Application"
# identity, then run Scripts/notarize.sh on the resulting DMG.
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

version="${1:-1.1.0}"
identity="${CODE_SIGN_IDENTITY:--}"  # "-" = ad-hoc
dist="dist"
derived="$dist/DerivedData"
app="$derived/Build/Products/Release/Radix.app"
staging="$dist/staging"
dmg="$dist/Radix-$version.dmg"

rm -rf "$dist"
mkdir -p "$dist"

xcodegen generate
# With a Developer ID identity this produces a hardened-runtime, timestamped
# signature ready for notarization; with "-" it is an ad-hoc local build.
xcodebuild -project Radix.xcodeproj -scheme RadixApp -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
    CODE_SIGN_IDENTITY="$identity" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" OTHER_CODE_SIGN_FLAGS="--timestamp" build

mkdir -p "$staging"
cp -R "$app" "$staging/Radix.app"
ln -s /Applications "$staging/Applications"

hdiutil create -volname "Radix" -srcfolder "$staging" -ov -format UDZO "$dmg"
rm -rf "$staging"

if [ "$identity" != "-" ]; then
    codesign --force --timestamp --sign "$identity" "$dmg"
    codesign --verify --verbose=1 "$dmg"
fi

echo "Built $dmg"
shasum -a 256 "$dmg"
