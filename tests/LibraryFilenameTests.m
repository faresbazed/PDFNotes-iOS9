#import "LibraryNames.h"
#include <stdio.h>

static int failures;
static void Check(BOOL ok, const char *name) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok) failures++;
}

int main(void) {
    @autoreleasepool {
        NSArray *inputs = @[@".Thesis", @"..x", @".", @"...", @"  .x", @"", @" \n", @"Thesis.v2.pdf", @" a/b\\c:d*e "];
        NSArray *expected = @[@"Thesis", @"x", @"", @"", @"x", @"", @"", @"Thesis.v2.pdf", @"a-b-c-d-e"];
        for (NSUInteger i = 0; i < inputs.count; i++) {
            NSString *input = [inputs objectAtIndex:i];
            NSString *clean = PDFSanitizeLibraryFilename(input);
            Check([clean isEqual:[expected objectAtIndex:i]], [[NSString stringWithFormat:@"sanitize case %lu", (unsigned long)i] UTF8String]);
            Check(clean.length == 0 || ![clean hasPrefix:@"."], [[NSString stringWithFormat:@"visible or empty case %lu", (unsigned long)i] UTF8String]);
        }
        Check(PDFSanitizeLibraryFilename(nil).length == 0, "nil uses empty-name handling");
        Check(PDFLibraryNameIsReserved(PDFSanitizeLibraryFilename(@".Inbox")), "create validation sees sanitized reserved name");
        Check(PDFLibraryRenameNameIsReserved(PDFSanitizeLibraryFilename(@"..Annotations"), YES, @""), "root rename validation sees sanitized reserved name");
        Check(!PDFLibraryRenameNameIsReserved(PDFSanitizeLibraryFilename(@".Inbox"), NO, @""), "nested rename keeps existing reserved-name rule");
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        Check([fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL], "create fixture directory");
        NSString *name = [PDFSanitizeLibraryFilename(@".Thesis") stringByAppendingPathExtension:@"pdf"];
        Check([@"fixture" writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:NULL], "create sanitized PDF");
        NSString *folder = PDFSanitizeLibraryFilename(@"..x");
        Check([fm createDirectoryAtPath:[dir stringByAppendingPathComponent:folder] withIntermediateDirectories:NO attributes:nil error:NULL], "create sanitized folder");
        NSMutableArray *visible = [NSMutableArray array];
        for (NSString *entry in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
            if ([entry hasPrefix:@"."]) continue;
            [visible addObject:entry];
        }
        Check([visible containsObject:name], "library dot-file filter lists sanitized PDF");
        Check([visible containsObject:folder], "library dot-file filter lists sanitized folder");
        [fm removeItemAtPath:dir error:NULL];
    }
    printf("%d failures\n", failures);
    return failures ? 1 : 0;
}
