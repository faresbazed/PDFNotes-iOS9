# Foundation regression tests

Run from the repository root: `tests/run.sh`

On Ubuntu, install `clang libgnustep-base-dev` first. Tests compile the same
Foundation-only annotation file helper used by AnnotationStore; UIKit is not
required. Fixtures use a unique temporary Documents directory.
