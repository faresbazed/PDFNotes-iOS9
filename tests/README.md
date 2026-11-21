# Linux undo regressions

From the repository root:

```sh
./tests/run.sh
python3 tests/run_stroke_undo.py
```

Both tests require Python 3, clang and GNUstep Foundation. Neither requires an
iOS SDK or tests rendering, disk persistence or UIKit behavior.

## Sticky-note drag undo (`run.sh`)

Requires GNUstep Foundation built with **libobjc2/ARC**.
`GNUSTEP_CONFIG` can select a different installation; the default is
`$HOME/gnustep/System/Tools/gnustep-config`. Ubuntu's stock GNUstep uses the
legacy GCC runtime and cannot compile the app's ARC/weak references.

The test compiles the real `src/Models.m`, disabling disk I/O/debouncing via a
store subclass. It also compiles the unmodified `noteBadgePanned:` method
extracted from `src/PageView.m`, with small stand-ins for the badge, gesture,
page coordinate conversion, and UIKit types. This prevents a model-only test
from missing a mutation made by the caller before invoking the store. All
shims are test-only; no iOS SDK or UI rendering is involved. Outputs go in
`build/tests/`.

The direct-store move/undo control distinguishes a caller ownership bug from
an undo implementation bug. The regression exercises preview, ended and
cancelled drags (both commit under existing behavior), undo/redo, and one-entry
history, plus empty pages, missing IDs and nonfinite positions.

## Stroke undo (`run_stroke_undo.py`)

Uses the system `gnustep-config` on `PATH` and Ubuntu's stock GNUstep/GCC
runtime. The runner extracts production stroke/history methods from
`src/Models.m`, desugars dictionary subscripting for the legacy runtime, and
compiles and executes the assertions. The fixture supplies legacy-runtime
ivars/properties, a copyable stroke payload in place of UIKit geometry, and an
in-memory store with persistence disabled. Generated files live in a temporary
directory and are removed automatically.

## One-time Ubuntu setup

Install the shared tools and system Foundation first. This is sufficient for
the stroke test:

```sh
sudo apt-get update
sudo apt-get install -y clang libgnustep-base-dev cmake ninja-build git libffi-dev libxml2-dev
```

For the sticky-note test, also build an isolated ARC-capable Foundation in your
home directory. It does not replace system libraries or change `PATH`, so the
stroke harness continues to use the system installation. Run outside the
repository:

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

TLS/ICU are not needed for this in-memory regression. CMake may fetch the
libobjc2 robin-map dependency if it is not installed already.

The app build remains `./build.sh` with the iOS SDK/toolchain installed.
