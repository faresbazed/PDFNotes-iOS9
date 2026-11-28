#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
awk '/^- \((void|NSUInteger)\)(renderPagesInRect:|updateVisiblePagesForceRender:|firstPageEndingAtOrAfterY:)/{p=1}
     p {print} /^}/{p=0}' src/ReaderViewController.m |
  sed 's/_pageFrames\[mid\]/[_pageFrames objectAtIndex:mid]/g; s/_pageFrames\[i\]/[_pageFrames objectAtIndex:i]/g; s/_loadedPages\[key\]/[_loadedPages objectForKey:key]/g' > "$out/window.inc"
clang $(gnustep-config --objc-flags) -I"$(gcc -print-file-name=include)" -I"$out" -Isrc \
    tests/reader-render.m -o "$out/test" $(gnustep-config --base-libs)
"$out/test"
