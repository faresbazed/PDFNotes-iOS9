#import "ReaderNavigation.h"

NSArray<NSNumber *> *PDFSavedPageRows(NSIndexSet *bookmarks, NSIndexSet *annotations,
                                     PDFSavedPageFilter filter, NSInteger pageCount) {
    NSIndexSet *pages;
    switch (filter) {
        case PDFSavedPageFilterBookmarks: pages = bookmarks; break;
        case PDFSavedPageFilterAnnotations: pages = annotations; break;
        default: {
            NSMutableIndexSet *combined = [NSMutableIndexSet indexSet];
            [combined addIndexes:bookmarks];
            [combined addIndexes:annotations];
            pages = combined;
            break;
        }
    }
    NSMutableArray *rows = [NSMutableArray array];
    NSUInteger limit = (NSUInteger)MAX(0, pageCount);
    for (NSUInteger i = pages.firstIndex; i < limit; i = [pages indexGreaterThanIndex:i]) {
        [rows addObject:@(i)];
    }
    return rows;
}

void PDFRecordPageJump(NSMutableArray<NSNumber *> *history, NSInteger from, NSInteger to, NSInteger pageCount) {
    if (from == to || from < 0 || to < 0 || from >= pageCount || to >= pageCount) return;
    if ([history.lastObject isEqual:@(from)]) return;
    if (history.count == 16) [history removeObjectAtIndex:0];
    [history addObject:@(from)];
}

NSUInteger PDFJumpBackIndex(NSArray<NSNumber *> *history, NSInteger currentPage) {
    for (NSUInteger i = history.count; i > 0; i--) {
        if ([[history objectAtIndex:i - 1] integerValue] != currentPage) return i - 1;
    }
    return NSNotFound;
}

CGFloat PDFPageJumpOffset(CGFloat pageTop, CGFloat pageHeight, CGFloat viewportHeight, CGFloat contentHeight, CGFloat topMargin) {
    CGFloat centered = pageTop + (pageHeight - viewportHeight) * 0.5f;
    CGFloat offset = MIN(pageTop - topMargin, centered);
    return MAX(0, MIN(offset, contentHeight - viewportHeight));
}

PDFReadingAnchor PDFCaptureReadingAnchor(NSInteger page, CGFloat pageTop, CGFloat pageHeight,
                                        CGFloat viewportTop, CGFloat viewportHeight) {
    CGFloat y = pageHeight < viewportHeight ? viewportTop + viewportHeight * 0.5f : viewportTop;
    y = MAX(pageTop, MIN(y, pageTop + pageHeight));
    return (PDFReadingAnchor){ page, (y - pageTop) / MAX(1, pageHeight),
                              (y - viewportTop) / MAX(1, viewportHeight) };
}

CGFloat PDFRestoreReadingOffset(PDFReadingAnchor anchor, CGFloat pageTop, CGFloat pageHeight,
                                CGFloat viewportHeight, CGFloat contentHeight) {
    CGFloat y = pageTop + anchor.pageFraction * pageHeight - anchor.viewportFraction * viewportHeight;
    return MAX(0, MIN(y, contentHeight - viewportHeight));
}
