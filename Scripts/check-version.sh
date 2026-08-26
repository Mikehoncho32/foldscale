#!/usr/bin/env bash
# Every place a version lives must agree: project.yml, the site's fallbacks, the newest
# released CHANGELOG section and the newest appcast item. CI runs this on every PR.
set -euo pipefail
cd "$(dirname "$0")/.."
v="$(Scripts/version.sh)"
b="$(Scripts/version.sh --build)"
fail=0
complain() { echo "check-version: $*" >&2; fail=1; }

for id in version version2; do
    grep -q "id=\"$id\">$v<" site/index.html || complain "site/index.html #$id is not $v"
done
if grep -o 'Foldscale-[0-9][0-9.]*\.dmg' site/index.html | grep -qv "^Foldscale-$v\.dmg$"; then
    complain "site/index.html links a DMG other than Foldscale-$v.dmg"
fi
newest="$(grep -m1 -o '^## \[[0-9][^]]*\]' CHANGELOG.md | tr -d '#[] ')"
[ "$newest" = "$v" ] || complain "newest released CHANGELOG section is [$newest], project.yml says $v"
xmllint --noout site/appcast.xml || complain "site/appcast.xml is not well-formed"
if grep -q '<item>' site/appcast.xml; then
    sv="$(xmllint --xpath 'string(//item[1]/*[local-name()="shortVersionString"])' site/appcast.xml)"
    bv="$(xmllint --xpath 'string(//item[1]/*[local-name()="version"])' site/appcast.xml)"
    [ "$sv" = "$v" ] || complain "newest appcast item is $sv, project.yml says $v"
    [ "$bv" = "$b" ] || complain "newest appcast build is $bv, project.yml says $b"
fi
[ "$fail" = 0 ] && echo "check-version: everything agrees on $v (build $b)"
exit "$fail"
