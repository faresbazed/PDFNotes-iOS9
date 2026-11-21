#!/usr/bin/env python3
"""Exercise extracted production rename/sweep logic without UIKit or ARC."""
from pathlib import Path
import re
import shlex
import subprocess

root = Path(__file__).resolve().parent.parent
source = (root / 'src/LibraryViewController.m').read_text()


def body(signature):
    start = source.index('{', source.index(signature)) + 1
    depth = 1
    end = start
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end - 1]


rename = body('- (void)promptRenameItem:')
rename = rename[rename.index('NSString *clean ='):rename.rindex('    }]];')]
rename = rename.replace('[sSelf sanitizeFilename:ac.textFields.firstObject.text]', 'Sanitize(typed)')
rename = rename.replace('item.fullPath', 'fullPath').replace('item.isDirectory', 'isDirectory')
rename = rename.replace('[sSelf showReservedNameAlert];', '')
rename = rename.replace('[AnnotationStore documentsDirectory]', 'docs')
rename = re.sub(r'UIAlertController \*exists =.*?\[sSelf presentViewController:exists animated:YES completion:nil\];', '', rename, flags=re.S)
rename = rename.replace('return;', 'return NO;')
rename = rename.replace('[AnnotationStore moveAnnotationsFromPath:fullPath toPath:newPath isDirectory:isDirectory];',
                        'PDFMoveAnnotations(fullPath, newPath, isDirectory, docs, [NSUserDefaults standardUserDefaults]);')
rename = rename.replace('[sSelf reloadFiles];', 'return YES;')
sweep = body('- (void)sweepInboxIfNeeded')
sweep = sweep.replace('if (![self isRootLibrary]) return;', '')
sweep = sweep.replace('NSString *docs = [AnnotationStore documentsDirectory];', '')
sweep = sweep.replace('[self uniqueDestinationInDirectory:docs forFilename:name]', 'Unique(docs, name)')
out = root / 'build/tests/library-names'
out.mkdir(parents=True, exist_ok=True)
helper = root / 'src/LibraryNames.m'
generated = '#import <Foundation/Foundation.h>\n#import "AnnotationFiles.h"\n'
if helper.exists():
    generated += '#import "LibraryNames.h"\n'
    assert 'PDFLibraryNameIsReserved(folderName)' in body('- (void)promptCreateNewFolder')
generated += 'static NSString *docs;\n'
generated += 'static NSString *Sanitize(NSString *input) {' + body('- (NSString *)sanitizeFilename:') + '}\n'
generated += 'static NSString *Unique(NSString *dir, NSString *filename) {' + body('- (NSString *)uniqueDestinationInDirectory:') + '}\n'
generated += 'static BOOL Rename(NSString *fullPath, BOOL isDirectory, NSString *typed) {' + rename + 'return NO;}\n'
generated += 'static void Sweep(void) {' + sweep + '}\n'
generated += (root / 'tests/LibraryNamesTests.m').read_text()
(out / 'main.m').write_text(generated)
flags = lambda arg: shlex.split(subprocess.check_output(['gnustep-config', arg], text=True))
subprocess.run(['clang', *flags('--objc-flags'), '-I' + subprocess.check_output(['gcc', '-print-file-name=include'], text=True).strip(),
                '-I' + str(root / 'src'), str(out / 'main.m'), str(root / 'src/AnnotationFiles.m'),
                *([str(helper)] if helper.exists() else []), '-o', str(out / 'tests'), *flags('--base-libs')], check=True)
raise SystemExit(subprocess.run([str(out / 'tests')]).returncode)
