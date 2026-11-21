#import "LibraryNames.h"

BOOL PDFLibraryNameIsReserved(NSString *name) {
    NSString *lower = name.lowercaseString;
    return [lower isEqualToString:@"inbox"] || [lower isEqualToString:@"annotations"];
}

BOOL PDFLibraryRenameNameIsReserved(NSString *name, BOOL rootLibrary, NSString *relativeFolder) {
    return rootLibrary && relativeFolder.length == 0 && PDFLibraryNameIsReserved(name);
}
