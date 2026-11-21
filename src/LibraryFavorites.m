#import "LibraryFavorites.h"

static NSString *const FavoritesKey = @"library.favoritePDFPaths";

static BOOL VisibleRelativePath(NSString *relative) {
    NSArray<NSString *> *parts = [relative componentsSeparatedByString:@"/"];
    if ([parts.firstObject isEqualToString:@"Inbox"] || [parts.firstObject isEqualToString:@"Annotations"]) return NO;
    for (NSString *part in parts) {
        if (!part.length || [part hasPrefix:@"."]) return NO;
    }
    return YES;
}

static NSString *RelativePath(NSString *path, NSString *documents) {
    NSString *prefix = [documents stringByAppendingString:@"/"];
    return [path hasPrefix:prefix] ? [path substringFromIndex:prefix.length] : nil;
}

static NSSet<NSString *> *SavedPaths(NSUserDefaults *defaults) {
    NSArray *paths = [defaults stringArrayForKey:FavoritesKey];
    return paths ? [NSSet setWithArray:paths] : [NSSet set];
}

NSSet<NSString *> *PDFLibraryFavoritePaths(NSString *documents, NSUserDefaults *defaults) {
    NSMutableSet *paths = [NSMutableSet set];
    for (NSString *relative in SavedPaths(defaults)) {
        if (VisibleRelativePath(relative) && [relative.pathExtension.lowercaseString isEqualToString:@"pdf"]) {
            [paths addObject:[documents stringByAppendingPathComponent:relative]];
        }
    }
    return paths;
}

NSArray<NSString *> *PDFAvailableFavoriteDocuments(NSSet<NSString *> *favoritePaths, NSString *documents) {
    NSMutableArray *available = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in favoritePaths) {
        NSString *resolved = [path stringByResolvingSymlinksInPath];
        NSString *relative = RelativePath(resolved, documents);
        if (!relative || !VisibleRelativePath(relative)) continue;
        NSDictionary *attrs = [fm attributesOfItemAtPath:resolved error:NULL];
        if ([[attrs objectForKey:NSFileType] isEqualToString:NSFileTypeRegular]) [available addObject:path];
    }
    return available;
}

void PDFSetLibraryFavorite(NSString *path, BOOL favorite, NSString *documents, NSUserDefaults *defaults) {
    NSString *relative = RelativePath(path, documents);
    if (!relative || !VisibleRelativePath(relative) || ![relative.pathExtension.lowercaseString isEqualToString:@"pdf"]) return;
    NSMutableSet *paths = [NSMutableSet setWithSet:SavedPaths(defaults)];
    if (favorite) [paths addObject:relative];
    else [paths removeObject:relative];
    [defaults setObject:paths.allObjects forKey:FavoritesKey];
}

void PDFRelocateLibraryFavorites(NSString *from, NSString *to, BOOL directory, NSString *documents, NSUserDefaults *defaults) {
    NSString *old = RelativePath(from, documents);
    NSString *dest = RelativePath(to, documents);
    if (!old.length || (to && !dest.length)) return;
    NSSet *saved = SavedPaths(defaults);
    NSMutableSet *paths = [NSMutableSet setWithSet:saved];
    NSString *prefix = [old stringByAppendingString:@"/"];
    for (NSString *relative in saved) {
        if (!(directory ? [relative hasPrefix:prefix] : [relative isEqualToString:old])) continue;
        [paths removeObject:relative];
        if (dest) [paths addObject:[dest stringByAppendingString:[relative substringFromIndex:old.length]]];
    }
    if (![paths isEqualToSet:saved]) [defaults setObject:paths.allObjects forKey:FavoritesKey];
}
