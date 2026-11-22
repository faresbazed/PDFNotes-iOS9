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
. "$ROOT/tests/arc_model.inc" persistence
