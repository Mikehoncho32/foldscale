#!/usr/bin/env bash
#
# Builds Radix in Release and packages it into a distributable DMG.
#
#   Scripts/build-dmg.sh [version]
#
# Unsigned/ad-hoc by default. For a shippable build set:
#   CODE_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"   # sign app + DMG
#   NOTARY_PROFILE=radix-notary                                     # also notarize + staple
# (store the profile once: xcrun notarytool store-credentials radix-notary \
#    --apple-id you@example.com --team-id TEAMID)
#
# Order matters for notarization: sign app → notarize app → staple app → build
# DMG → sign DMG → notarize DMG → staple DMG, so both the app and the DMG carry a
# ticket and open cleanly even offline.
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

version="${1:-1.1.0}"
identity="${CODE_SIGN_IDENTITY:--}"  # "-" = ad-hoc
profile="${NOTARY_PROFILE:-}"
dist="dist"
derived="$dist/DerivedData"
app="$derived/Build/Products/Release/Radix.app"
staging="$dist/staging"
dmg="$dist/Radix-$version.dmg"

rm -rf "$dist"
mkdir -p "$dist"

xcodegen generate
# Build unsigned: the local SPM package (RadixCore) is auto-signed by xcodebuild
# and rejects a manually specified identity. The finished app is signed below.
xcodebuild -project Radix.xcodeproj -scheme RadixApp -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO build

mkdir -p "$staging"
cp -R "$app" "$staging/Radix.app"

if [ "$identity" != "-" ]; then
    # Developer ID + hardened runtime + trusted timestamp: ready for notarization.
    codesign --force --options runtime --timestamp --sign "$identity" "$staging/Radix.app"
else
    codesign --force --sign - "$staging/Radix.app"
fi
codesign --verify --deep --strict --verbose=1 "$staging/Radix.app"

if [ -n "$profile" ]; then
    echo "== notarizing app =="
    ditto -c -k --keepParent "$staging/Radix.app" "$dist/Radix-app.zip"
    xcrun notarytool submit "$dist/Radix-app.zip" --keychain-profile "$profile" --wait
    xcrun stapler staple "$staging/Radix.app"
    rm -f "$dist/Radix-app.zip"
fi

ln -s /Applications "$staging/Applications"
hdiutil create -volname "Radix" -srcfolder "$staging" -ov -format UDZO "$dmg"
rm -rf "$staging"

if [ "$identity" != "-" ]; then
    codesign --force --timestamp --sign "$identity" "$dmg"
    codesign --verify --verbose=1 "$dmg"
fi

if [ -n "$profile" ]; then
    echo "== notarizing DMG =="
    xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
fi

echo "Built $dmg"
shasum -a 256 "$dmg"
