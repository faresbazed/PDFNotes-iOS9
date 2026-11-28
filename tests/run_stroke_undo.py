#!/usr/bin/env python3
"""Run the production stroke/history methods with GNUstep Foundation on Linux."""
import pathlib
import re
import shlex
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
source = (ROOT / "src/Models.m").read_text()
names = [
    "deepCopyStrokes", "deepCopyNotes", "pushEditAction", "pushUndoForPage", "strokesForPage",
    "addStroke", "replaceStrokes", "clearPage", "hasAnnotations", "swapAnnotationsForDocumentEdit",
    "clearAllAnnotations", "canUndo", "canRedo",
    "applyStateForPage", "undoReturningPage", "redoReturningPage",
]
methods = []
for name in names:
    match = re.search(r"^[+-] \([^\n]+?\)" + name + r"\b.*?^}", source, re.M | re.S)
    if not match:
        raise RuntimeError(f"Cannot find model method {name}")
    method = match.group()
    # Ubuntu's legacy Objective-C runtime lacks keyed subscripting. Desugar only
    # these dictionary accesses; the model's mutation and history logic is intact.
    method = re.sub(r"(_(?:strokes|notes)ByPage)\[pk\] = (.*);",
                    r"[\1 setObject:\2 forKey:pk];", method)
    method = re.sub(r"(_(?:strokes|notes)ByPage)\[pk\]",
                    r"[\1 objectForKey:pk]", method)
    methods.append(method)

fixture = (ROOT / "tests/stroke_undo.m").read_text()
program = fixture.replace("// MODEL_METHODS", "\n\n".join(methods))
flags = shlex.split(subprocess.check_output(["gnustep-config", "--objc-flags"], text=True))
libs = shlex.split(subprocess.check_output(["gnustep-config", "--base-libs"], text=True))
objc_headers = subprocess.check_output(["gcc", "-print-file-name=include"], text=True).strip()
with tempfile.TemporaryDirectory(prefix="stroke-undo-") as directory:
    path = pathlib.Path(directory)
    (path / "test.m").write_text(program)
    subprocess.run(["clang", *flags, "-I" + objc_headers, str(path / "test.m"),
                    "-o", str(path / "test"), *libs], check=True, cwd=path)
    raise SystemExit(subprocess.run([str(path / "test")]).returncode)
