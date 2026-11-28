#import "LibraryListing.h"
#import "AnnotationFiles.h"
#include <unistd.h>

static int failures;
static void Check(BOOL ok, const char *message) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", message);
    if (!ok) failures++;
}

static void Seed(NSString *docs) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *rel in @[@"Course/Week", @"Course/.hidden", @"Inbox", @"Annotations"]) {
        [fm createDirectoryAtPath:[docs stringByAppendingPathComponent:rel] withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    for (NSString *rel in @[@"Course/Week/Notes.PDF", @"Course/.hidden/Hidden.pdf", @"Inbox/Import.pdf", @"Course/NotPDF.txt"]) {
        [fm createFileAtPath:[docs stringByAppendingPathComponent:rel] contents:nil attributes:nil];
    }
    NSString *template = [docs stringByAppendingPathComponent:@".fixture.plist"];
    NSString *payload = [@"12345678 " stringByPaddingToLength:512*1024 withString:@"12345678 " startingAtIndex:0];
    [@{@"pages": @{@"0": @[payload]}, @"lastPage": @7} writeToFile:template atomically:YES];
    for (int i = 0; i < 400; i++) {
        NSString *name = [NSString stringWithFormat:@"Course/Lecture-%03d.pdf", i];
        NSString *path = [docs stringByAppendingPathComponent:name];
        [fm createFileAtPath:path contents:nil attributes:nil];
        if (i == 0) Check(truncate(path.fileSystemRepresentation, 512LL * 1024 * 1024) == 0, "large sparse PDF fixture");
        NSString *key = [PDFAnnotationKey(path, docs) stringByAppendingPathExtension:@"plist"];
        NSString *ann = [[docs stringByAppendingPathComponent:@"Annotations"] stringByAppendingPathComponent:key];
        if (link(template.fileSystemRepresentation, ann.fileSystemRepresentation) != 0) failures++;
    }
}

@interface CancelEarly : NSOperation { int _checks; }
@end
@implementation CancelEarly
- (BOOL)isCancelled { return ++_checks >= 12; }
@end

int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc != 3) return 2;
    NSString *docs = [[NSString stringWithUTF8String:argv[1]] stringByResolvingSymlinksInPath];
    NSString *mode = [NSString stringWithUTF8String:argv[2]];
    if ([mode isEqual:@"seed"]) {
        Seed(docs);
        return failures != 0;
    }
    NSString *folder = [docs stringByAppendingPathComponent:@"Course"];
    NSArray *items = PDFScanLibrary(folder, docs, NO, nil, nil);
    Check(items.count == 401, "crowded folder lists PDFs and immediate folders only");
    for (PDFLibraryItem *item in items) {
        if (item.detailsLoaded || item.relativeFolder.length) failures++;
        if ([item.name isEqual:@"Lecture-000"]) Check(item.fileSize == 512ULL * 1024 * 1024, "large PDF size without loading its contents");
    }
    if ([mode isEqual:@"scan"]) return failures != 0;
    items = PDFScanLibrary(docs, docs, YES, nil, nil);
    Check(items.count == 403, "recursive search excludes hidden and reserved trees");
    NSString *nested = [folder stringByAppendingPathComponent:@"Week/Notes.PDF"];
    items = PDFScanLibrary(docs, docs, NO, [NSSet setWithObject:nested], nil);
    PDFLibraryItem *favorite = items.firstObject;
    Check(items.count == 1 && [favorite.fullPath isEqual:nested] && [favorite.relativeFolder isEqual:@"Course/Week"], "favorites retain the relative folder");
    NSArray *partial = PDFScanLibrary(folder, docs, YES, nil, [[CancelEarly alloc] init]);
    Check(partial.count < 12, "superseded scan stops during enumeration");
    NSOperation *cancelled = [[NSOperation alloc] init];
    [cancelled cancel];
    Check(PDFScanLibrary(folder, docs, NO, nil, cancelled).count == 0, "cancelled scan does not start listing");

    NSString *pdf = [folder stringByAppendingPathComponent:@"Lecture-000.pdf"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *pref = [@"lastPage." stringByAppendingString:PDFAnnotationKey(pdf, docs)];
    [defaults removeObjectForKey:pref];
    NSInteger page = -1;
    Check(PDFReadLibraryAnnotationSummary(pdf, docs, defaults, &page) && page == 7, "visible row gets badge and sidecar page");
    [defaults setInteger:0 forKey:pref];
    Check(PDFReadLibraryAnnotationSummary(pdf, docs, defaults, &page) && page == 0, "live page preference overrides sidecar");
    [defaults removeObjectForKey:pref];
    Check(!PDFReadLibraryAnnotationSummary(nested, docs, defaults, &page) && page == 0, "missing sidecar yields no badge");
    NSString *linkedFolder = [docs stringByAppendingPathComponent:@"Week alias.pdf"];
    Check(symlink("Course/Week", linkedFolder.fileSystemRepresentation) == 0, "linked folder fixture");
    for (NSString *target in @[@"Annotations", @"Course/.hidden", @"..", @"nonexistent"]) {
        NSString *name = [@"alias-" stringByAppendingFormat:@"%@.pdf", target.lastPathComponent];
        Check(symlink(target.fileSystemRepresentation, [docs stringByAppendingPathComponent:name].fileSystemRepresentation) == 0, "unavailable or non-library link fixture");
    }
    BOOL foundFolder = NO;
    for (PDFLibraryItem *item in PDFScanLibrary(docs, docs, NO, nil, nil)) {
        if ([item.fullPath isEqual:linkedFolder]) foundFolder = item.isDirectory && [item.name isEqual:@"Week alias.pdf"];
    }
    Check(foundFolder, "link to a folder appears as a navigable folder even with a PDF suffix");
    items = PDFScanLibrary(linkedFolder, docs, NO, nil, nil);
    Check(items.count == 1 && [[[items firstObject] fullPath] isEqual:[linkedFolder stringByAppendingPathComponent:@"Notes.PDF"]],
          "browsing a linked folder preserves its visible path");
    Check(PDFScanLibrary(docs, docs, YES, nil, nil).count == 404, "recursive search lists the folder link without following it twice");
    return failures != 0;
}}
