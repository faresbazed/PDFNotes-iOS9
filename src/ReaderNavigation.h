#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, PDFSavedPageFilter) {
    PDFSavedPageFilterAll,
    PDFSavedPageFilterBookmarks,
    PDFSavedPageFilterAnnotations,
};

NSArray<NSNumber *> *PDFSavedPageRows(NSIndexSet *bookmarks, NSIndexSet *annotations,
                                     PDFSavedPageFilter filter, NSInteger pageCount);
void PDFRecordPageJump(NSMutableArray<NSNumber *> *history, NSInteger from, NSInteger to, NSInteger pageCount);
NSUInteger PDFJumpBackIndex(NSArray<NSNumber *> *history, NSInteger currentPage);
