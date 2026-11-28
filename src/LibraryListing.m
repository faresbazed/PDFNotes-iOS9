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
    if (operation.cancelled) return items;
    if (favorites) {
        for (NSString *path in PDFAvailableFavoriteDocuments(favorites, documents)) {
            if (operation.cancelled) break;
            NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
            [items addObject:Item(path, [path substringFromIndex:documents.length + 1], attrs, NO)];
        }
        return items;
    }

    BOOL root = [directory isEqualToString:documents];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:directory];
    NSString *relative;
    while (!operation.cancelled && (relative = [enumerator nextObject])) {
        @autoreleasepool {
            if ([relative.lastPathComponent hasPrefix:@"."] ||
                (root && ([relative isEqualToString:@"Inbox"] || [relative isEqualToString:@"Annotations"]))) {
                [enumerator skipDescendents];
                continue;
            }
            NSDictionary *attrs = enumerator.fileAttributes;
            BOOL isDir = [[attrs fileType] isEqualToString:NSFileTypeDirectory];
            if (isDir && !recursive) [enumerator skipDescendents];
            if (!isDir && ![relative.pathExtension.lowercaseString isEqualToString:@"pdf"]) continue;
            [items addObject:Item([directory stringByAppendingPathComponent:relative], relative, attrs, isDir)];
        }
    }
    return items;
}
