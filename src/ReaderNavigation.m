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

PDFReadingReference PDFReadingReferenceForViewport(CGFloat viewportTop, CGFloat viewportHeight, CGFloat contentHeight,
                                                 CGFloat centeredPageTop, CGFloat centeredPageHeight) {
    if (viewportTop <= 0.5f) return PDFReadingDocumentStart;
    if (viewportTop + viewportHeight >= contentHeight - 0.5f) return PDFReadingDocumentEnd;
    CGFloat midY = viewportTop + viewportHeight * 0.5f;
    if (centeredPageHeight < viewportHeight && midY >= centeredPageTop && midY <= centeredPageTop + centeredPageHeight) {
        return PDFReadingSlideCenter;
    }
    return PDFReadingTopLine;
}

CGFloat PDFRestoreReadingOffset(PDFReadingAnchor anchor, CGFloat pageTop, CGFloat pageHeight,
                                CGFloat viewportHeight, CGFloat contentHeight) {
    if (anchor.reference == PDFReadingDocumentStart) return 0;
    if (anchor.reference == PDFReadingDocumentEnd) return MAX(0, contentHeight - viewportHeight);
    CGFloat y = pageTop + anchor.pageFraction * pageHeight;
    if (anchor.reference == PDFReadingSlideCenter) y -= viewportHeight * 0.5f;
    return MAX(0, MIN(y, contentHeight - viewportHeight));
}
