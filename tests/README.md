# Sticky-note drag undo regression (Linux)

From the repository root:

```sh
./tests/run.sh
```

Requires Python 3, clang, and GNUstep Foundation built with **libobjc2/ARC**.
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

## One-time Ubuntu setup

The following builds an isolated Foundation installation in your home directory
(does not replace system libraries). Run outside the repository:

```sh
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build git libffi-dev libxml2-dev
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
. "$HOME/gnustep/System/Library/Makefiles/GNUstep.sh"
cd ../base
./configure --disable-tls --disable-icu CC=clang CXX=clang++ \
  CPPFLAGS="-I$HOME/gnustep/include" \
  LDFLAGS="-L$HOME/gnustep/lib -Wl,-rpath,$HOME/gnustep/lib"
make -j4
make install
```

TLS/ICU are not needed for this in-memory regression. CMake may fetch the
libobjc2 robin-map dependency if it is not installed already.
