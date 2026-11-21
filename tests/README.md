# Linux model regression tests

From the repository root:

```sh
./tests/run.sh                     # Library favorites, names and annotation files (system GNUstep)
python3 tests/run_stroke_undo.py    # Stroke undo (system GNUstep)
./tests/run_drag_undo.sh            # Sticky-note drag undo (libobjc2/ARC GNUstep)
```

All tests use clang and GNUstep Foundation; none requires an iOS SDK or tests
rendering or UIKit behavior. The two GNUstep installations remain separate
because Ubuntu's stock GCC runtime cannot compile the app's ARC/weak references.

## Annotation files (`run.sh`)

Compiles the production Foundation-only annotation file helper used by
AnnotationStore. Fixtures use a unique temporary Documents directory. Tests
cover key escaping, deletion, renaming and migration, including collision and
retry cases. Outputs go in `build/tests/annotation-tests`.

`run.sh` also compiles `LibraryNamesTests.m` directly with the production
Foundation-only `LibraryNames.m` helper. It checks case-insensitive reserved
names, ordinary/PDF/empty names, and the root-vs-nested rename rule, including
nested results in root-library searches. Outputs go in `build/tests/library-name-tests`.
There is no source extraction. UIKit caller wiring, filesystem operations and
alert presentation are not exercised by these unit tests. Create continues to
reject reserved names at all levels.

## Stroke undo (`run_stroke_undo.py`)

Uses the system `gnustep-config` on `PATH` and Ubuntu's stock GNUstep/GCC
runtime. The runner extracts production stroke/history methods from
`src/Models.m`, desugars dictionary subscripting for the legacy runtime, and
compiles and executes the assertions. The fixture supplies legacy-runtime
ivars/properties, a copyable stroke payload in place of UIKit geometry, and an
in-memory store with persistence disabled. Generated files live in a temporary
directory and are removed automatically.

## Sticky-note drag undo (`run_drag_undo.sh`)

Requires GNUstep Foundation built with **libobjc2/ARC**. `GNUSTEP_CONFIG` can
select a different installation; the default is
`$HOME/gnustep/System/Tools/gnustep-config`. The other runners use the system
`gnustep-config` on `PATH` instead.

Compiles the real `src/Models.m` and `src/AnnotationFiles.m`, disabling store
disk I/O/debouncing via a subclass. It also compiles the unmodified
`noteBadgePanned:` method extracted from `src/PageView.m`, with test-only
stand-ins for the badge, gesture, page coordinate conversion and UIKit types.
This prevents a model-only test from missing a mutation made by the caller
before invoking the store. Outputs go in `build/tests/drag-undo` without
overwriting the annotation test binary.

The direct-store move/undo control distinguishes a caller ownership bug from
an undo implementation bug. The regression exercises preview, ended and
cancelled drags (both commit under existing behavior), undo/redo, and one-entry
history, plus empty pages, missing IDs and nonfinite positions. It does not
test disk persistence.

## One-time Ubuntu setup

Install the shared tools and system Foundation first. This is sufficient for
the annotation and stroke tests:

```sh
sudo apt-get update
sudo apt-get install -y clang libgnustep-base-dev cmake ninja-build git libffi-dev libxml2-dev
```

For the sticky-note test, also build an isolated ARC-capable Foundation in your
home directory. It does not replace system libraries or change the parent
shell's `PATH`. Run outside the repository:

```sh
mkdir -p "$HOME/gnustep-src"
cd "$HOME/gnustep-src"
git clone --depth 1 --branch v2.2.1 https://github.com/gnustep/libobjc2.git
git clone --depth 1 --branch make-2_9_2 https://github.com/gnustep/tools-make.git make
git clone --depth 1 --branch base-1_30_0 https://github.com/gnustep/libs-base.git base
cmake -S libobjc2 -B libobjc2/build -G Ninja \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_INSTALL_PREFIX="$HOME/gnustep" -DCMAKE_INSTALL_LIBDIR=lib \
  -DGNUSTEP_INSTALL_TYPE=NONE -DTESTS=OFF
cmake --build libobjc2/build -j4
cmake --install libobjc2/build
cd make
./configure --prefix="$HOME/gnustep" --with-layout=gnustep \
  --with-library-combo=ng-gnu-gnu CC=clang CXX=clang++ \
  CPPFLAGS="-I$HOME/gnustep/include" \
  LDFLAGS="-L$HOME/gnustep/lib -Wl,-rpath,$HOME/gnustep/lib"
make install
(
. "$HOME/gnustep/System/Library/Makefiles/GNUstep.sh"
cd ../base
./configure --disable-tls --disable-icu CC=clang CXX=clang++ \
  CPPFLAGS="-I$HOME/gnustep/include" \
  LDFLAGS="-L$HOME/gnustep/lib -Wl,-rpath,$HOME/gnustep/lib"
make -j4
make install
)
```

TLS/ICU are not needed for the sticky-note regression. CMake may fetch the
libobjc2 robin-map dependency if it is not installed already.

The app build remains `./build.sh` with the iOS SDK/toolchain installed.
