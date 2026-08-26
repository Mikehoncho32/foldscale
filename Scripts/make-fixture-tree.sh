#!/usr/bin/env bash
#
# Generates deterministic fixture trees for FoldscaleCore.
#
#   make-fixture-tree.sh golden <dir>            # small, known-shape reference tree
#   make-fixture-tree.sh large  <dir> [copies]   # ~copies*10,100 + 50,000 nodes
#
# The "golden" tree contains known sizes, a hard link, and a symlink, so its total
# can be cross-checked against `du`. (Unit tests build their own equivalent fixtures
# in Swift; this script is for the benchmark and for manual du-parity checks.)
#
# A truly dataless (SF_DATALESS) cloud file cannot be created here — that flag is
# owned by the kernel/File Provider and cannot be set with chflags. Cloud handling
# is unit-tested by decoding a hand-built stat instead (see ModelTests).
set -euo pipefail

mode="${1:-golden}"
dest="${2:?usage: make-fixture-tree.sh <golden|large> <dir> [copies]}"

make_golden() {
    local root="$1"
    mkdir -p "$root/sub"
    head -c 300000 /dev/zero >"$root/big.bin"
    head -c 10 /dev/zero >"$root/small.txt"
    head -c 50000 /dev/zero >"$root/sub/nested.dat"
    ln "$root/big.bin" "$root/big.hardlink"   # hard link (deduped)
    ln -s "sub" "$root/sub.symlink"           # symlink (not followed)
    echo "golden fixture ready at $root"
}

make_large() {
    local root="$1" copies="${2:-100}"
    local template="$root/_template"

    # Template: 100 dirs × 100 empty files ≈ 10,100 nodes.
    mkdir -p "$template"
    for d in $(seq -w 1 100); do
        mkdir -p "$template/dir$d"
        for f in $(seq -w 1 100); do : >"$template/dir$d/file$f.dat"; done
    done

    # Replicate via APFS clonefile (cp -c) — copy-on-write, fast.
    for c in $(seq -w 1 "$copies"); do
        cp -c -R "$template" "$root/copy$c"
    done
    rm -rf "$template"

    # One wide directory (50,000 entries) for the sort benchmark.
    mkdir -p "$root/wide"
    for f in $(seq 1 50000); do : >"$root/wide/f$f"; done

    echo "large fixture ready at $root (~$((copies * 10100 + 50000)) nodes)"
}

mkdir -p "$dest"
case "$mode" in
    golden) make_golden "$dest" ;;
    large) make_large "$dest" "${3:-100}" ;;
    *) echo "unknown mode: $mode (expected golden or large)" >&2; exit 2 ;;
esac
