# Linux model regression

Install dependencies and run from the repository root:

```sh
sudo apt-get update
sudo apt-get install -y clang libgnustep-base-dev
python3 tests/run_stroke_undo.py
```

The runner extracts the production stroke/history methods from `src/Models.m`
at runtime, compiles them with GNUstep Foundation, and executes the assertions.
It desugars dictionary subscripting for Ubuntu's legacy Objective-C runtime.
The fixture supplies legacy-runtime ivars/properties, a copyable stroke payload
in place of UIKit geometry, and an in-memory store with persistence disabled.
It does not test rendering, disk persistence, or UIKit. Generated files live in
a temporary directory and are removed automatically. The app build remains
`./build.sh` with the iOS SDK/toolchain installed.
