#import "LibraryFavorites.h"

static NSString *const FavoritesKey = @"library.favoritePDFPaths";

static BOOL VisibleRelativePath(NSString *relative) {
    if (!relative.length) return NO;
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

static NSString *RelativeEntry(NSString *path, NSString *documents, NSMutableDictionary *parents) {
    if (!VisibleRelativePath(RelativePath(path, documents))) return nil;
    // Resolve the parent only: a link entry can be renamed/deleted without changing its target.
    NSString *folder = path.stringByDeletingLastPathComponent;
    NSString *parent = [parents objectForKey:folder];
    if (!parent) {
        parent = [folder stringByResolvingSymlinksInPath];
        if (!parent) return nil;
        [parents setObject:parent forKey:folder];
    }
    NSString *relative = RelativePath([parent stringByAppendingPathComponent:path.lastPathComponent], documents);
    return VisibleRelativePath(relative) ? relative : nil;
}

static NSMutableSet<NSString *> *SavedPaths(NSString *documents, NSUserDefaults *defaults) {
    NSMutableSet *paths = [NSMutableSet set];
    NSMutableDictionary *parents = [NSMutableDictionary dictionary];
    for (NSString *relative in [defaults stringArrayForKey:FavoritesKey]) {
        if (!VisibleRelativePath(relative) || ![relative.pathExtension.lowercaseString isEqualToString:@"pdf"]) continue;
        NSString *entry = RelativeEntry([documents stringByAppendingPathComponent:relative], documents, parents);
        if (entry) [paths addObject:entry];
    }
    return paths;
}

NSSet<NSString *> *PDFLibraryFavoritePaths(NSString *documents, NSUserDefaults *defaults) {
    NSMutableSet *paths = [NSMutableSet set];
    for (NSString *relative in SavedPaths(documents, defaults)) {
        [paths addObject:[documents stringByAppendingPathComponent:relative]];
    }
    return paths;
}

NSDictionary *PDFVisibleLibraryTargetAttributes(NSString *path, NSString *documents) {
    NSString *resolved = [path stringByResolvingSymlinksInPath];
    NSString *relative = RelativePath(resolved, documents);
    if (!relative || !VisibleRelativePath(relative)) return nil;
    return [[NSFileManager defaultManager] attributesOfItemAtPath:resolved error:NULL];
}

void PDFSetLibraryFavorite(NSString *path, BOOL favorite, NSString *documents, NSUserDefaults *defaults) {
    NSString *relative = RelativeEntry(path, documents, nil);
    if (!relative || ![relative.pathExtension.lowercaseString isEqualToString:@"pdf"]) return;
    NSMutableSet *paths = SavedPaths(documents, defaults);
    if (favorite) [paths addObject:relative];
    else [paths removeObject:relative];
    [defaults setObject:paths.allObjects forKey:FavoritesKey];
}

void PDFRelocateLibraryFavorites(NSString *from, NSString *to, BOOL directory, NSString *documents, NSUserDefaults *defaults) {
    NSString *old = RelativeEntry(from, documents, nil);
    NSString *dest = to ? RelativeEntry(to, documents, nil) : nil;
    if (!old.length || (to && !dest.length)) return;
    NSSet *saved = SavedPaths(documents, defaults);
    NSMutableSet *paths = [NSMutableSet setWithSet:saved];
    NSString *prefix = [old stringByAppendingString:@"/"];
    for (NSString *relative in saved) {
        if (!(directory ? [relative hasPrefix:prefix] : [relative isEqualToString:old])) continue;
        [paths removeObject:relative];
        if (dest) [paths addObject:[dest stringByAppendingString:[relative substringFromIndex:old.length]]];
    }
    if (![paths isEqualToSet:saved]) [defaults setObject:paths.allObjects forKey:FavoritesKey];
}
