#import <Foundation/Foundation.h>
#import "LibraryNames.h"

static int failures;
static void Check(BOOL ok, NSString *message) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", message.UTF8String);
    if (!ok) failures++;
}

int main(void) { @autoreleasepool {
    for (NSString *name in @[@"Inbox", @"Annotations", @"inbox", @"ANNOTATIONS", @"iNbOx", @"aNnOtAtIoNs"]) {
        Check(PDFLibraryNameIsReserved(name), [NSString stringWithFormat:@"%@ is reserved", name]);
    }
    for (NSString *name in @[@"Reading", @"Inbox.pdf", @"Annotations.pdf", @"Inbox2", @"", @".Inbox"]) {
        Check(!PDFLibraryNameIsReserved(name), [NSString stringWithFormat:@"'%@' is not reserved", name]);
    }
    Check(!PDFLibraryNameIsReserved(nil), @"nil is not reserved");
    Check(PDFLibraryRenameNameIsReserved(@"Inbox", YES, @""), @"root rename to Inbox is reserved");
    Check(PDFLibraryRenameNameIsReserved(@"ANNOTATIONS", YES, @""), @"root rename to ANNOTATIONS is reserved");
    Check(!PDFLibraryRenameNameIsReserved(@"Inbox", NO, @""), @"nested library allows Inbox");
    Check(!PDFLibraryRenameNameIsReserved(@"Annotations", YES, @"Course/Week2"), @"nested search result allows Annotations");
    Check(!PDFLibraryRenameNameIsReserved(@"Reading", YES, @""), @"ordinary root rename allowed");
    Check(!PDFLibraryRenameNameIsReserved(@"Inbox.pdf", YES, @""), @"root Inbox.pdf allowed");
    printf("Library names: %d failures\n", failures);
    return failures ? 1 : 0;
}}
