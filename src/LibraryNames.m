#import "LibraryNames.h"

BOOL PDFLibraryNameIsReserved(NSString *name) {
    NSString *lower = name.lowercaseString;
    return [lower isEqualToString:@"inbox"] || [lower isEqualToString:@"annotations"];
}
