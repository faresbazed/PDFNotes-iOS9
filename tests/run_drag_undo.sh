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
. "$ROOT/tests/arc_model.inc" drag-undo
