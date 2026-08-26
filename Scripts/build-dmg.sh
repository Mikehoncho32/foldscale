#!/usr/bin/env bash
#
# Builds Foldscale in Release and packages it into a distributable DMG.
#
#   Scripts/build-dmg.sh            # version comes from project.yml (Scripts/version.sh)
#   Scripts/build-dmg.sh 1.3.0      # optional: assert that project.yml says this version
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

version="$(Scripts/version.sh)"
if [ -n "${1:-}" ] && [ "$1" != "$version" ]; then
    echo "Requested $1 but project.yml says $version — run Scripts/set-version.sh $1 first" >&2
    exit 1
fi
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

# Sparkle keys must have made it into the bundle (xcodegen `info:` block), or the
# shipped app could never update.
for key in SUFeedURL SUPublicEDKey; do
    /usr/libexec/PlistBuddy -c "Print :$key" "$staging/Foldscale.app/Contents/Info.plist" >/dev/null \
        || { echo "Info.plist is missing $key" >&2; exit 1; }
done

# Sparkle ships pre-signed by Sparkle's team. Hardened-runtime library validation
# refuses frameworks from another team, so re-sign every nested component
# inside-out with OUR identity — never --deep (Downloader.xpc carries its own
# entitlements). Order and flags per sparkle-project.org/documentation/sandboxing.
fw="$staging/Foldscale.app/Contents/Frameworks/Sparkle.framework"
[ -d "$fw" ] || { echo "Sparkle.framework is not embedded — check project.yml" >&2; exit 1; }
# Inside-out order; "entitlements" marks the one component whose entitlements must survive.
sparkle_parts=(
    "$fw/Versions/B/XPCServices/Installer.xpc"
    "$fw/Versions/B/XPCServices/Downloader.xpc|entitlements"
    "$fw/Versions/B/Autoupdate"
    "$fw/Versions/B/Updater.app"
    "$fw"
)

# One field of `codesign -d` output (TeamIdentifier, Timestamp…). sed drains the whole
# stream, so this is safe under pipefail (grep -q would SIGPIPE codesign → status 141).
sig_field() { codesign -dvv "$1" 2>&1 | sed -n "s/^$2=//p"; }
team_of() { sig_field "$1" TeamIdentifier; }

# Sign with a trusted timestamp, retrying: Apple's timestamp server sometimes refuses
# (codesign exits 1) and sometimes answers nothing (codesign exits 0 without a
# Timestamp field — which --verify does NOT catch). Notarization rejects either.
sign_ts() {  # $1 = path; rest = extra codesign flags
    local target="$1" attempt
    shift
    for attempt in 1 2 3 4 5; do
        if codesign --force --timestamp --sign "$identity" "$@" "$target" \
            && [ -n "$(sig_field "$target" Timestamp)" ]; then
            return 0
        fi
        [ "$attempt" -lt 5 ] || { echo "no trusted timestamp on $target after 5 attempts" >&2; return 1; }
        echo "no trusted timestamp on $target (attempt $attempt); retrying in 20 s" >&2
        sleep 20
    done
}

for part in "${sparkle_parts[@]}"; do
    path="${part%%|*}"
    extra=()
    [ "${part#*|}" = entitlements ] && extra=(--preserve-metadata=entitlements)
    if [ "$identity" != "-" ]; then
        sign_ts "$path" -o runtime "${extra[@]}"
    else
        codesign -f -s - "${extra[@]}" "$path"
    fi
done
if [ "$identity" != "-" ]; then
    # Developer ID + hardened runtime + trusted timestamp: ready for notarization.
    sign_ts "$staging/Foldscale.app" -o runtime
else
    codesign --force --sign - "$staging/Foldscale.app"
fi
codesign --verify --deep --strict --verbose=1 "$staging/Foldscale.app"

# Library validation: the framework must carry the same TeamIdentifier as the app.
app_team="$(team_of "$staging/Foldscale.app")"
sparkle_team="$(team_of "$fw")"
if [ "$app_team" != "$sparkle_team" ]; then
    echo "TeamIdentifier mismatch: app=$app_team sparkle=$sparkle_team" >&2; exit 1
fi

if [ -n "$profile" ]; then
    echo "== notarizing app =="
    ditto -c -k --keepParent "$staging/Foldscale.app" "$dist/Foldscale-app.zip"
    xcrun notarytool submit "$dist/Foldscale-app.zip" --keychain-profile "$profile" --wait
    xcrun stapler staple "$staging/Foldscale.app"
    rm -f "$dist/Foldscale-app.zip"
    spctl --assess --type execute --verbose=2 "$staging/Foldscale.app"  # expect: Notarized Developer ID
fi

ln -s /Applications "$staging/Applications"
hdiutil create -volname "Foldscale" -srcfolder "$staging" -ov -format UDZO "$dmg"
rm -rf "$staging"

if [ "$identity" != "-" ]; then
    sign_ts "$dmg"
    codesign --verify --verbose=1 "$dmg"
fi
        echo "DMG signature has no timestamp (attempt $attempt); retrying in 20 s" >&2
        sleep 20
    done
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
