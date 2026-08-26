#!/usr/bin/env bash
#
# Builds Foldscale in Release and packages it into a distributable DMG.
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

version="${1:-1.2.0}"
identity="${CODE_SIGN_IDENTITY:--}"  # "-" = ad-hoc
profile="${NOTARY_PROFILE:-}"
dist="dist"
derived="$dist/DerivedData"
app="$derived/Build/Products/Release/Foldscale.app"
staging="$dist/staging"
dmg="$dist/Foldscale-$version.dmg"

rm -rf "$dist"
mkdir -p "$dist"

xcodegen generate
# Build unsigned: the local SPM package (FoldscaleCore) is auto-signed by xcodebuild
# and rejects a manually specified identity. The finished app is signed below.
xcodebuild -project Foldscale.xcodeproj -scheme FoldscaleApp -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO build

mkdir -p "$staging"
cp -R "$app" "$staging/Foldscale.app"

if [ "$identity" != "-" ]; then
    # Developer ID + hardened runtime + trusted timestamp: ready for notarization.
    codesign --force --options runtime --timestamp --sign "$identity" "$staging/Foldscale.app"
else
    codesign --force --sign - "$staging/Foldscale.app"
fi
codesign --verify --deep --strict --verbose=1 "$staging/Foldscale.app"

if [ -n "$profile" ]; then
    echo "== notarizing app =="
    ditto -c -k --keepParent "$staging/Foldscale.app" "$dist/Foldscale-app.zip"
    xcrun notarytool submit "$dist/Foldscale-app.zip" --keychain-profile "$profile" --wait
    xcrun stapler staple "$staging/Foldscale.app"
    rm -f "$dist/Foldscale-app.zip"
fi

ln -s /Applications "$staging/Applications"
hdiutil create -volname "Foldscale" -srcfolder "$staging" -ov -format UDZO "$dmg"
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
