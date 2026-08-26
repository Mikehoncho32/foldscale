#!/usr/bin/env bash
# Prepends one release to the Sparkle feed (site/appcast.xml, ADR-0005).
#
#   Scripts/appcast.sh <version> <dmg> [--out FILE] [--url URL] [--build N]
#                      [--signature SIG --length BYTES] [--notes-file MD] [--force]
#
# Signs the DMG with the EdDSA key (Sparkle's sign_update, key in the login keychain),
# renders the CHANGELOG section for <version> to HTML with GitHub's markdown API, and
# inserts an <item> at the top of the feed, keeping the newest 10. --force replaces an
# existing item for the same version (re-run after a failed release).
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: appcast.sh <version> <dmg> [options]}"
dmg="${2:?usage: appcast.sh <version> <dmg> [options]}"
shift 2
out=site/appcast.xml url="" build="" sig="" len="" notes="" force=0
while [ $# -gt 0 ]; do
    case "$1" in
        --out) out="$2"; shift 2 ;;
        --url) url="$2"; shift 2 ;;
        --build) build="$2"; shift 2 ;;
        --signature) sig="$2"; shift 2 ;;
        --length) len="$2"; shift 2 ;;
        --notes-file) notes="$2"; shift 2 ;;
        --force) force=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
if [ -z "$build" ]; then
    project="$(Scripts/version.sh)"
    [ "$version" = "$project" ] || { echo "project.yml says $project, not $version" >&2; exit 1; }
    build="$(Scripts/version.sh --build)"
fi
[ -n "$url" ] || url="https://github.com/Mikehoncho32/foldscale/releases/download/v$version/Foldscale-$version.dmg"

# 1. EdDSA signature.
if [ -z "$sig" ]; then
    bin="${SPARKLE_BIN:-}"
    for candidate in dist/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin \
        "$HOME"/Library/Developer/Xcode/DerivedData/Foldscale-*/SourcePackages/artifacts/sparkle/Sparkle/bin; do
        [ -n "$bin" ] || { [ -x "$candidate/sign_update" ] && bin="$candidate"; }
    done
    [ -n "$bin" ] || { echo "sign_update not found — build once (Scripts/build-dmg.sh) or set SPARKLE_BIN" >&2; exit 1; }
    line="$("$bin/sign_update" "$dmg")"
    sig="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$line")"
    len="$(sed -n 's/.*length="\([^"]*\)".*/\1/p' <<<"$line")"
    [ -n "$sig" ] && [ -n "$len" ] || { echo "could not parse sign_update output: $line" >&2; exit 1; }
fi
[ -n "$len" ] || len="$(stat -f%z "$dmg")"

# 2. Release notes → HTML (GitHub's renderer; plain <pre> if offline).
if [ -z "$notes" ]; then
    notes="$(mktemp)"
    Scripts/changelog-section.sh "$version" > "$notes"
fi
html="$(gh api -X POST /markdown -f mode=gfm -f context=Mikehoncho32/foldscale -F "text=@$notes" 2>/dev/null || true)"
[ -n "$html" ] || html="<pre>$(sed 's/&/\&amp;/g; s/</\&lt;/g' "$notes")</pre>"
html="${html//]]>/]]]]><![CDATA[>}"

# 3. The item.
pub="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
item="$(mktemp)"
{
    printf '    <item>\n'
    printf '      <title>Foldscale %s</title>\n' "$version"
    printf '      <pubDate>%s</pubDate>\n' "$pub"
    printf '      <sparkle:version>%s</sparkle:version>\n' "$build"
    printf '      <sparkle:shortVersionString>%s</sparkle:shortVersionString>\n' "$version"
    printf '      <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>\n'
    printf '      <link>https://github.com/Mikehoncho32/foldscale/releases/tag/v%s</link>\n' "$version"
    printf '      <description><![CDATA[%s]]></description>\n' "$html"
    printf '      <enclosure url="%s" length="%s" type="application/octet-stream" sparkle:edSignature="%s"/>\n' \
        "$url" "$len" "$sig"
    printf '    </item>\n'
} > "$item"

# 4. Splice: drop a same-version item (only with --force), insert, keep 10.
marker="<sparkle:shortVersionString>$version</sparkle:shortVersionString>"
if grep -qF "$marker" "$out"; then
    [ "$force" = 1 ] || { echo "$out already has $version; pass --force to replace it" >&2; exit 1; }
fi
tmp="$(mktemp)"
awk -v marker="$marker" -v item="$item" '
    /<item>/ { in_item = 1; buf = ""; drop = 0 }
    in_item {
        buf = buf $0 "\n"
        if (index($0, marker)) drop = 1
        if (/<\/item>/) { in_item = 0; if (!drop) printf "%s", buf }
        next
    }
    { print }
    /<!-- items:begin -->/ { while ((getline line < item) > 0) print line; close(item) }' "$out" > "$tmp"
awk '/<item>/ { n++; if (n > 10) skip = 1 } !skip { print } /<\/item>/ { skip = 0 }' "$tmp" > "$out"
rm -f "$tmp" "$item"

# 5. Sanity.
xmllint --noout "$out"
newest="$(xmllint --xpath 'string(//item[1]/*[local-name()="shortVersionString"])' "$out")"
[ "$newest" = "$version" ] || { echo "newest item is $newest, expected $version" >&2; exit 1; }
echo "$out: Foldscale $version (build $build), $len bytes, $(grep -c '<item>' "$out") item(s)"
