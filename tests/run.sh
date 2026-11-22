#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
clang $(gnustep-config --objc-flags) -I"$(gcc -print-file-name=include)" -Isrc \
    tests/LibraryFavoritesTests.m src/LibraryFavorites.m -o build/tests/library-favorites-tests $(gnustep-config --base-libs)
build/tests/library-favorites-tests
clang $(gnustep-config --objc-flags) -I"$(gcc -print-file-name=include)" -Isrc \
    tests/AnnotationFilesTests.m src/AnnotationFiles.m -o build/tests/annotation-tests $(gnustep-config --base-libs)
build/tests/annotation-tests
clang $(gnustep-config --objc-flags) -I"$(gcc -print-file-name=include)" -Isrc \
    tests/LibraryFilenameTests.m src/LibraryNames.m -o build/tests/library-filename-tests $(gnustep-config --base-libs)
build/tests/library-filename-tests
clang $(gnustep-config --objc-flags) -I"$(gcc -print-file-name=include)" -Isrc \
    tests/LibraryNamesTests.m src/LibraryNames.m -o build/tests/library-name-tests $(gnustep-config --base-libs)
build/tests/library-name-tests
clang $(gnustep-config --objc-flags) -I"$(gcc -print-file-name=include)" -Isrc \
    tests/LibraryFilesTests.m src/LibraryFiles.m src/AnnotationFiles.m -o build/tests/library-file-tests $(gnustep-config --base-libs)
build/tests/library-file-tests
