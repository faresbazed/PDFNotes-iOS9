#import "LibraryListing.h"
#import "LibraryFavorites.h"

@implementation PDFLibraryItem
@synthesize name = _name, fullPath = _fullPath, relativeFolder = _relativeFolder, modDate = _modDate;
@synthesize fileSize = _fileSize, isDirectory = _isDirectory, detailsLoaded = _detailsLoaded;
@synthesize hasAnnotations = _hasAnnotations, lastPage = _lastPage, childCount = _childCount;
@end

static PDFLibraryItem *Item(NSString *path, NSString *relative, NSDictionary *attrs, BOOL directory) {
    PDFLibraryItem *item = [[PDFLibraryItem alloc] init];
    item.name = directory ? path.lastPathComponent : path.lastPathComponent.stringByDeletingPathExtension;
    item.fullPath = path;
    item.relativeFolder = relative.stringByDeletingLastPathComponent;
    item.isDirectory = directory;
    item.fileSize = [attrs fileSize];
    item.modDate = [attrs fileModificationDate] ?: [NSDate distantPast];
    return item;
}

NSMutableArray<PDFLibraryItem *> *PDFScanLibrary(NSString *directory, NSString *documents, BOOL recursive,
                                                NSSet<NSString *> *favorites, NSOperation *operation) {
    NSMutableArray *items = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([operation isCancelled]) return items;
    if (favorites) {
        for (NSString *path in favorites) {
            if ([operation isCancelled]) break;
            @autoreleasepool {
                NSDictionary *attrs = PDFVisibleLibraryTargetAttributes(path, documents);
                if ([[attrs fileType] isEqualToString:NSFileTypeRegular]) {
                    [items addObject:Item(path, [path substringFromIndex:documents.length + 1], attrs, NO)];
                }
            }
        }
        return items;
    }

    // Children have the same identity whether reached through a folder or its link.
    directory = [directory stringByResolvingSymlinksInPath];
    BOOL root = [directory isEqualToString:documents];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:directory];
    NSString *relative;
    while (![operation isCancelled] && (relative = [enumerator nextObject])) {
        @autoreleasepool {
            NSDictionary *attrs = enumerator.fileAttributes;
            BOOL isDir = [[attrs fileType] isEqualToString:NSFileTypeDirectory];
            if ([relative.lastPathComponent hasPrefix:@"."] ||
                (root && ([relative isEqualToString:@"Inbox"] || [relative isEqualToString:@"Annotations"]))) {
                if (isDir) [enumerator skipDescendents];
                continue;
            }
            if (isDir && !recursive) [enumerator skipDescendents];
            NSString *path = [directory stringByAppendingPathComponent:relative];
            if ([[attrs fileType] isEqualToString:NSFileTypeSymbolicLink]) {
                // The enumerator does not descend into links; a user can still browse one explicitly.
                attrs = PDFVisibleLibraryTargetAttributes(path, documents);
                isDir = [[attrs fileType] isEqualToString:NSFileTypeDirectory];
                if (!isDir && ![[attrs fileType] isEqualToString:NSFileTypeRegular]) continue;
            }
            if (!isDir && ![relative.pathExtension.lowercaseString isEqualToString:@"pdf"]) continue;
            [items addObject:Item(path, relative, attrs, isDir)];
        }
    }
    return items;
}
