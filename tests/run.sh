#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
clang $(gnustep-config --objc-flags) -I"$(gcc -print-file-name=include)" -Isrc \
    tests/AnnotationFilesTests.m src/AnnotationFiles.m -o build/tests/annotation-tests $(gnustep-config --base-libs)
build/tests/annotation-tests
