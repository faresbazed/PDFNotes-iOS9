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
typedef struct { CGFloat start, end; } PDFDocumentBounds;
CGFloat PDFPageEdgePadding(CGFloat pageHeight, CGFloat zoomScale, CGFloat viewportHeight, CGFloat minimum);
CGFloat PDFPageJumpOffset(CGFloat pageTop, CGFloat pageHeight, CGFloat viewportHeight, PDFDocumentBounds bounds, CGFloat topMargin);

typedef NS_ENUM(NSInteger, PDFReadingReference) {
    PDFReadingTopLine, PDFReadingSlideCenter, PDFReadingDocumentStart, PDFReadingDocumentEnd,
};

typedef struct {
    NSInteger page;
    CGFloat pageFraction;
    PDFReadingReference reference;
} PDFReadingAnchor;

PDFReadingReference PDFReadingReferenceForViewport(CGFloat viewportTop, CGFloat viewportHeight, PDFDocumentBounds bounds,
                                                 CGFloat centeredPageTop, CGFloat centeredPageHeight);
CGFloat PDFRestoreReadingOffset(PDFReadingAnchor anchor, CGFloat pageTop, CGFloat pageHeight,
                                CGFloat viewportHeight, PDFDocumentBounds bounds);
