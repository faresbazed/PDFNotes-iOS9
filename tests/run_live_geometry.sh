#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

# Compile the complete production methods: in particular, do not reconstruct
# the coalesced event loop or choose when to freeze/publish in the fixture.
awk '/^static (CGFloat gMainScreenScale|const NSUInteger kLiveSegmentPoints) =/{print}
     /^static void PDFSetInkBounds\(/{p=1} p{print} /^}/{p=0}' src/PageView.m > "$out/constants.inc"
awk '/^- \([^)]*\)(isDrawingOrAnnotatingTool|newLiveSegment|displayLivePath|freezeLiveSegment|displayLiveTip|finishLivePathAtPoint|touchesBegan|touchesMoved)[: ]/{p=1}
     p{print} /^}/{p=0}' src/PageView.m > "$out/touch.inc"
clang $(gnustep-config --objc-flags) -I"$(gcc -print-file-name=include)" -I"$out" \
    tests/live-geometry.m -o "$out/test" $(gnustep-config --base-libs)
"$out/test"
