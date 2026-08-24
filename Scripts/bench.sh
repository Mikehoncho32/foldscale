#!/usr/bin/env bash
#
# Runs the ADR-0001 node-layout benchmark: builds radix-bench in release, generates
# (or reuses) a ~1M-node fixture, and reports scan time + peak RSS for both the
# struct-of-arrays and class-per-node layouts. Peak RSS comes from `/usr/bin/time -l`
# ("maximum resident set size", in bytes on macOS).
#
#   Scripts/bench.sh                 # default ~1.06M-node fixture in $TMPDIR
#   RADIX_COPIES=50 Scripts/bench.sh # smaller fixture
#   RADIX_FIXTURE=/path Scripts/bench.sh
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

fixture="${RADIX_FIXTURE:-${TMPDIR:-/tmp}/radix-fixture-large}"
copies="${RADIX_COPIES:-100}"
bin=".build/release/radix-bench"

echo "== building radix-bench (release) =="
swift build -c release --product radix-bench

if [ ! -d "$fixture" ]; then
    echo "== generating fixture ($copies copies) =="
    Scripts/make-fixture-tree.sh large "$fixture" "$copies"
else
    echo "== reusing fixture at $fixture =="
fi

echo
echo "== struct-of-arrays =="
/usr/bin/time -l "$bin" soa "$fixture" 2>&1 | grep -E "layout=|maximum resident"
echo
echo "== class-per-node =="
/usr/bin/time -l "$bin" class "$fixture" 2>&1 | grep -E "layout=|maximum resident"
