#!/usr/bin/env bash
# Exercises Scripts/appcast.sh without Sparkle, a DMG or the network: twelve synthetic
# releases go in, the newest ten stay, newest first, and --force replaces in place.
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
feed="$tmp/appcast.xml"
sed '/<item>/,/<\/item>/d' site/appcast.xml > "$feed"   # start from an empty channel
printf -- '- test note with <html> & "quotes"\n' > "$tmp/notes.md"
for i in $(seq 1 12); do
    Scripts/appcast.sh "9.0.$i" /dev/null --out "$feed" --build "$((100 + i))" \
        --signature "SIG$i" --length "$i" --url "https://example.invalid/Foldscale-9.0.$i.dmg" \
        --notes-file "$tmp/notes.md" > /dev/null
done
count="$(grep -c '<item>' "$feed")"
[ "$count" = 10 ] || { echo "expected 10 items, got $count" >&2; exit 1; }
newest="$(xmllint --xpath 'string(//item[1]/*[local-name()="shortVersionString"])' "$feed")"
[ "$newest" = "9.0.12" ] || { echo "newest item is $newest" >&2; exit 1; }
oldest="$(xmllint --xpath 'string(//item[10]/*[local-name()="shortVersionString"])' "$feed")"
[ "$oldest" = "9.0.3" ] || { echo "oldest kept item is $oldest" >&2; exit 1; }
if Scripts/appcast.sh 9.0.12 /dev/null --out "$feed" --build 112 --signature X --length 1 \
    --notes-file "$tmp/notes.md" > /dev/null 2>&1; then
    echo "re-adding an existing version without --force should fail" >&2; exit 1
fi
Scripts/appcast.sh 9.0.12 /dev/null --out "$feed" --build 112 --signature REPLACED --length 1 \
    --url "https://example.invalid/Foldscale-9.0.12.dmg" --notes-file "$tmp/notes.md" --force > /dev/null
[ "$(grep -c '<item>' "$feed")" = 10 ] || { echo "--force must replace, not add" >&2; exit 1; }
grep -q 'sparkle:edSignature="REPLACED"' "$feed" || { echo "--force did not replace the item" >&2; exit 1; }
grep -q 'test note' "$feed" || { echo "release notes missing from description" >&2; exit 1; }
xmllint --noout "$feed"
echo "appcast-test: ok"
