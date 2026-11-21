#import "LibraryFilename.h"

NSString *PDFSanitizeLibraryFilename(NSString *input) {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*"];
    NSString *clean = [[trimmed componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@"-"];
    NSUInteger start = 0;
    while (start < clean.length && [clean characterAtIndex:start] == '.') start++;
    return [clean substringFromIndex:start];
}
