#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
# Blocks are called in-place by the test dispatcher; no block runtime API is needed.
mkdir "$out/objc"
touch "$out/objc/blocks_runtime.h"
awk '/^- \(void\)(removePendingInkLayers:|invalidateInkBitmap |scheduleInkRender |releaseContent )/{p=1}
     p {print} /^}/{p=0}' src/PageView.m |
  sed 's/__weak typeof/typeof/g; s/_pendingInkLayers\[i\]/[_pendingInkLayers objectAtIndex:i]/g' > "$out/scheduler.inc"
clang $(gnustep-config --objc-flags) -fblocks -I"$(gcc -print-file-name=include)" -I"$out" \
    tests/ink-render.m -o "$out/test" $(gnustep-config --base-libs)
"$out/test"
