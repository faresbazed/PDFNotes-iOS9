#import "AnnotationFiles.h"
#import "LibraryFiles.h"
#include <sys/stat.h>
#include <unistd.h>

static int failures;
static void Check(BOOL ok, const char *message) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", message);
    if (!ok) failures++;
}
static void Write(NSString *path, NSString *value) {
    if (![value writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]) abort();
}
static NSString *Read(NSString *path) {
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
}

int main(void) { @autoreleasepool {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *docs = [root stringByAppendingPathComponent:@"Documents"];
    for (NSString *dir in @[@"Annotations", @"Class", @"Inbox/Folder", @"Inbox/Folder.pdf"]) {
        if (![fm createDirectoryAtPath:[docs stringByAppendingPathComponent:dir] withIntermediateDirectories:YES
                            attributes:nil error:NULL]) abort();
    }

    NSString *source = [docs stringByAppendingPathComponent:@"Inbox/Lecture.PDF"];
    NSString *existing = [docs stringByAppendingPathComponent:@"Lecture.PDF"];
    NSString *numbered = [docs stringByAppendingPathComponent:@"Lecture-2.PDF"];
    NSArray *ignored = @[@"Inbox/Folder/Work.pdf", @"Inbox/Folder.pdf/More.pdf", @"Inbox/title.txt", @"Inbox/.hidden.pdf"];
    for (NSString *name in ignored) Write([docs stringByAppendingPathComponent:name], @"keep");
    Write(source, @"incoming"); Write(existing, @"original");

    if (geteuid() != 0) {
        if (chmod(docs.fileSystemRepresentation, 0555)) abort();
        NSError *error = nil;
        Check(!PDFImportDocument(source, docs, &error) && error && [Read(source) isEqual:@"incoming"] &&
              ![fm fileExistsAtPath:numbered], "a failed handoff leaves the source in Inbox and returns an error");
        PDFImportInboxDocuments(docs);
        Check([Read(source) isEqual:@"incoming"], "a failed sweep also leaves the source for retry");
        if (chmod(docs.fileSystemRepresentation, 0755)) abort();
    }
    PDFImportInboxDocuments(docs);
    Check([Read(existing) isEqual:@"original"] && [Read(numbered) isEqual:@"incoming"] &&
          ![fm fileExistsAtPath:source], "sweep moves a PDF once without overwriting its namesake");
    for (NSString *name in ignored) {
        Check([Read([docs stringByAppendingPathComponent:name]) isEqual:@"keep"], name.UTF8String);
    }

    NSString *external = [root stringByAppendingPathComponent:@"Lecture.PDF"];
    Write(external, @"external");
    NSString *copied = PDFImportDocument(external, docs, NULL);
    Check([copied.lastPathComponent isEqual:@"Lecture-3.PDF"] && [Read(copied) isEqual:@"external"] &&
          [Read(external) isEqual:@"external"], "external handoff copies rather than moving its source");
    NSError *copyError = nil;
    Check(!PDFImportDocument(external, existing, &copyError) && copyError && [Read(external) isEqual:@"external"],
          "unusable destination does not return an external source as a successful import");
    Check([PDFImportDocument(copied, docs, NULL) isEqual:copied], "open-in-place document is not copied again");
    NSString *noExt = [docs stringByAppendingPathComponent:@"Inbox/Untitled"];
    Write(noExt, @"PDF without extension");
    Check([PDFImportDocument(noExt, docs, NULL).lastPathComponent isEqual:@"Untitled.pdf"] &&
          ![fm fileExistsAtPath:noExt], "explicit Inbox handoff keeps the PDF extension fallback");

    NSString *folder = [docs stringByAppendingPathComponent:@"Class"];
    NSString *pdf = [folder stringByAppendingPathComponent:@"Notes.pdf"];
    NSString *sidecar = [docs stringByAppendingPathComponent:@"Annotations/Class%2FNotes.pdf.plist"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *lastPage = @"lastPage.Class%2FNotes.pdf";
    [defaults setInteger:9 forKey:lastPage];
    Write(sidecar, @"annotations");
    NSError *deleteError = nil;
    Check(!PDFDeleteLibraryItem(pdf, NO, docs, defaults, &deleteError) && deleteError &&
          [Read(sidecar) isEqual:@"annotations"] && [defaults integerForKey:lastPage] == 9,
          "a failed stale-row delete preserves sidecar and reading position");
    Write(pdf, @"page");
    if (geteuid() != 0) {
        if (chmod(folder.fileSystemRepresentation, 0555)) abort();
        Check(!PDFDeleteLibraryItem(pdf, NO, docs, defaults, NULL) && [Read(pdf) isEqual:@"page"] &&
              [Read(sidecar) isEqual:@"annotations"] && [defaults integerForKey:lastPage] == 9,
              "a PDF that cannot be deleted retains its annotations and reading position");
        if (chmod(folder.fileSystemRepresentation, 0755)) abort();
    }
    Check(PDFDeleteLibraryItem(pdf, NO, docs, defaults, NULL) && ![fm fileExistsAtPath:pdf] &&
          ![fm fileExistsAtPath:sidecar] && ![defaults objectForKey:lastPage], "successful delete cleans associated state");
    Write(pdf, @"page"); Write(sidecar, @"annotations"); [defaults setInteger:2 forKey:lastPage];
    if (geteuid() != 0) {
        if (chmod(docs.fileSystemRepresentation, 0555)) abort();
        Check(!PDFDeleteLibraryItem(folder, YES, docs, defaults, NULL) && [Read(pdf) isEqual:@"page"] &&
              [Read(sidecar) isEqual:@"annotations"] && [defaults integerForKey:lastPage] == 2,
              "failure to remove a folder from its parent does not partially delete its contents");
        if (chmod(docs.fileSystemRepresentation, 0755)) abort();
    }
    Check(PDFDeleteLibraryItem(folder, YES, docs, defaults, NULL) && ![fm fileExistsAtPath:folder] &&
          ![fm fileExistsAtPath:sidecar] && ![defaults objectForKey:lastPage], "successful folder deletion cleans child state");
    [defaults removeObjectForKey:lastPage];
    [fm removeItemAtPath:root error:NULL];
    return failures ? 1 : 0;
}}
