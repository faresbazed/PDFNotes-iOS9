#import "LibraryNames.h"

NSString *PDFSanitizeLibraryFilename(NSString *input) {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*"];
    NSString *clean = [[trimmed componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@"-"];
    NSUInteger start = 0;
    while (start < clean.length && [clean characterAtIndex:start] == '.') start++;
    return [clean substringFromIndex:start];
}

BOOL PDFLibraryNameIsReserved(NSString *name) {
    NSString *lower = name.lowercaseString;
    return [lower isEqualToString:@"inbox"] || [lower isEqualToString:@"annotations"];
}

BOOL PDFLibraryRenameNameIsReserved(NSString *name, BOOL rootLibrary, NSString *relativeFolder) {
    return rootLibrary && relativeFolder.length == 0 && PDFLibraryNameIsReserved(name);
}
