# Linux model regression tests

From the repository root:

```sh
./tests/run.sh                     # Library favorites, names and annotation files (system GNUstep)
python3 tests/run_stroke_undo.py    # Stroke undo (system GNUstep)
./tests/run_ink_render.sh          # Ink render scheduling (system GNUstep)
./tests/run_live_geometry.sh       # Live pen/marker geometry (system GNUstep)
./tests/run_reader_render.sh       # Reader bitmap limits and viewport scheduling (system GNUstep)
./tests/run_drag_undo.sh            # Sticky-note drag undo (libobjc2/ARC GNUstep)
./tests/run_persistence.sh          # Annotation autosave, lifecycle and retry (libobjc2/ARC GNUstep)
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

The library file tests exercise actual Inbox moves, external copies, and PDF
and folder deletion in a temporary library. Run as a non-root user to also
exercise denied writes and deletes; root can bypass directory permissions.

## Stroke undo (`run_stroke_undo.py`)

Uses the system `gnustep-config` on `PATH` and Ubuntu's stock GNUstep/GCC
runtime. The runner extracts production stroke/history methods from
`src/Models.m`, desugars dictionary subscripting for the legacy runtime, and
compiles and executes the assertions. The fixture supplies legacy-runtime
ivars/properties, a copy-counting stroke payload in place of UIKit geometry, and an
in-memory store with persistence disabled. Generated files live in a temporary
directory and are removed automatically.

## Ink render scheduling (`run_ink_render.sh`)

Runs the production PageView scheduling, invalidation and release methods with a
controlled dispatcher. Images are ordered lists of stroke IDs; an edit can be
injected after a worker finishes but before its result reaches the UI. This
exercises rapid pen lifts, idle flush, deferral during active ink, stale timers,
append coalescing, staged erase/cancel, clear, eviction, resize, and
allocation failure. It does not test UIKit pixels, frame rate or touch latency.

The live geometry runner drives the production touch handlers with coalesced
samples, recording path commands and layer settings instead of pixels. It
checks that the active tip follows accepted samples, segments join across batch
boundaries, marker opacity applies once, and a fast down/up dash keeps its end.

The reader render runner exercises the production raster sizing code across
ordinary and extreme aspect ratios. It also drives the reader's viewport
methods with fake pages, checking visible-before-prefetch ordering, no new
prefetch during motion, offscreen eviction, and HUD updates on page changes.
It measures neither Core Graphics decode time nor on-device frame rate.

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

## Autosave and lifecycle

`run_persistence.sh` uses the same ARC installation and UIKit stand-ins, but
executes the real model, debounce timer and disk writer in a temporary library.
It holds a background write open across Home, warm resume and further edits,
then reopens the file after the protected snapshots finish. A UIKit test double
tracks background-task grants, denial, expiration and exactly-once endings;
the host does not simulate iOS suspension. A second fixture runs the reader's
open method with controlled queues and a real annotation store, including Back
before decoding and before publication. A directory obstructing the
sidecar tests failed writes and retry without another edit. The printed
30,000-point autosave callback timing measures the host, not iPad frame time.

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
