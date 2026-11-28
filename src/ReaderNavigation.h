#import <Foundation/Foundation.h>
#if defined(__APPLE__)
#import <CoreGraphics/CGBase.h>
#endif

typedef NS_ENUM(NSInteger, PDFSavedPageFilter) {
    PDFSavedPageFilterAll,
    PDFSavedPageFilterBookmarks,
    PDFSavedPageFilterAnnotations,
};

NSArray<NSNumber *> *PDFSavedPageRows(NSIndexSet *bookmarks, NSIndexSet *annotations,
                                     PDFSavedPageFilter filter, NSInteger pageCount);
void PDFRecordPageJump(NSMutableArray<NSNumber *> *history, NSInteger from, NSInteger to, NSInteger pageCount);
NSUInteger PDFJumpBackIndex(NSArray<NSNumber *> *history, NSInteger currentPage);
CGFloat PDFPageJumpOffset(CGFloat pageTop, CGFloat pageHeight, CGFloat viewportHeight, CGFloat contentHeight, CGFloat topMargin);
