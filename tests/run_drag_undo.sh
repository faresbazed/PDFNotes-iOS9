#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${GNUSTEP_CONFIG:-$HOME/gnustep/System/Tools/gnustep-config}"
if [[ ! -x "$CONFIG" ]]; then
    echo "Set GNUSTEP_CONFIG to gnustep-config for a libobjc2/ARC GNUstep installation (see tests/README.md)." >&2
    exit 2
fi
OUT="$ROOT/build/tests"
mkdir -p "$OUT"
python3 - "$ROOT/src/PageView.m" "$OUT/noteBadgePanned.inc" <<'PY'
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_text()
start = source.index('- (void)noteBadgePanned:')
opening = source.index('{', start)
depth = 1
end = opening + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
pathlib.Path(sys.argv[2]).write_text(source[start:end] + '\n')
PY
read -ra FLAGS <<< "$("$CONFIG" --objc-flags)"
read -ra LIBS <<< "$("$CONFIG" --base-libs)"
RPATHS=()
for flag in "${LIBS[@]}"; do
    [[ "$flag" != -L* ]] || RPATHS+=("-Wl,-rpath,${flag#-L}")
done
"${CC:-clang}" "${FLAGS[@]}" -fobjc-arc -fblocks -Wno-unused-parameter \
    -I"$ROOT/tests" -I"$ROOT/src" -I"$OUT" \
    "$ROOT/src/Models.m" "$ROOT/src/AnnotationFiles.m" "$ROOT/tests/UIKit.m" "$ROOT/tests/drag-undo.m" \
    -o "$OUT/drag-undo" "${LIBS[@]}" "${RPATHS[@]}"
"$OUT/drag-undo"
