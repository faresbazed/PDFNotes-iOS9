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

CGFloat PDFPageEdgePadding(CGFloat pageHeight, CGFloat zoomScale, CGFloat viewportHeight, CGFloat minimum) {
    return MAX(minimum, (viewportHeight - pageHeight * zoomScale) * 0.5f);
}

static CGFloat PDFClampOffset(CGFloat offset, CGFloat viewportHeight, PDFDocumentBounds bounds) {
    return MAX(bounds.start, MIN(offset, bounds.end - viewportHeight));
}

CGFloat PDFPageJumpOffset(CGFloat pageTop, CGFloat pageHeight, CGFloat viewportHeight, PDFDocumentBounds bounds, CGFloat topMargin) {
    CGFloat centered = pageTop + (pageHeight - viewportHeight) * 0.5f;
    CGFloat offset = MIN(pageTop - topMargin, centered);
    return PDFClampOffset(offset, viewportHeight, bounds);
}

PDFReadingReference PDFReadingReferenceForViewport(CGFloat viewportTop, CGFloat viewportHeight, PDFDocumentBounds bounds,
                                                 CGFloat centeredPageTop, CGFloat centeredPageHeight) {
    if (viewportTop <= bounds.start + 0.5f) return PDFReadingDocumentStart;
    if (viewportTop + viewportHeight >= bounds.end - 0.5f) return PDFReadingDocumentEnd;
    CGFloat midY = viewportTop + viewportHeight * 0.5f;
    if (centeredPageHeight < viewportHeight && midY >= centeredPageTop && midY <= centeredPageTop + centeredPageHeight) {
        return PDFReadingSlideCenter;
    }
    return PDFReadingTopLine;
}

CGFloat PDFRestoreReadingOffset(PDFReadingAnchor anchor, CGFloat pageTop, CGFloat pageHeight,
                                CGFloat viewportHeight, PDFDocumentBounds bounds) {
    if (anchor.reference == PDFReadingDocumentStart) return bounds.start;
    if (anchor.reference == PDFReadingDocumentEnd) return PDFClampOffset(bounds.end, viewportHeight, bounds);
    CGFloat y = pageTop + anchor.pageFraction * pageHeight;
    if (anchor.reference == PDFReadingSlideCenter) y -= viewportHeight * 0.5f;
    return PDFClampOffset(y, viewportHeight, bounds);
}
