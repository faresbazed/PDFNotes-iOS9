#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
bin=build/tests/library-listing-tests
clang $(gnustep-config --objc-flags) -I"$(gcc -print-file-name=include)" -Isrc \
    tests/LibraryListingTests.m src/LibraryListing.m src/LibraryFavorites.m src/AnnotationFiles.m \
    -o "$bin" $(gnustep-config --base-libs)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
"$bin" "$fixture" seed
"$bin" "$fixture" test
if command -v strace >/dev/null; then
    strace -qq -e trace=open,openat -o "$fixture/opens" "$bin" "$fixture" scan
    if grep -E "\"${fixture}/[^\"]*\.(pdf|plist)\"" "$fixture/opens"; then
        echo "Listing opened PDF or annotation contents" >&2
        exit 1
    fi
    echo 'PASS crowded-folder scan opens no PDF or annotation contents'
fi
