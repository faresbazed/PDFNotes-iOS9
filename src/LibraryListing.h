#import <Foundation/Foundation.h>

@interface PDFLibraryItem : NSObject {
    NSString *_name, *_fullPath, *_relativeFolder;
    NSDate *_modDate;
    unsigned long long _fileSize;
    BOOL _isDirectory, _detailsLoaded, _hasAnnotations;
    NSInteger _lastPage;
    NSUInteger _childCount;
}
@property (nonatomic, copy) NSString *name, *fullPath, *relativeFolder;
@property (nonatomic, strong) NSDate *modDate;
@property (nonatomic) unsigned long long fileSize;
@property (nonatomic) BOOL isDirectory;
// Filled on the main thread for displayed rows, never while enumerating a folder.
@property (nonatomic) BOOL detailsLoaded, hasAnnotations;
@property (nonatomic) NSInteger lastPage;
@property (nonatomic) NSUInteger childCount;
@end

// A nil favorites set lists the directory; an empty set lists no favorites.
NSMutableArray<PDFLibraryItem *> *PDFScanLibrary(NSString *directory, NSString *documents, BOOL recursive,
                                                NSSet<NSString *> *favorites, NSOperation *operation);
