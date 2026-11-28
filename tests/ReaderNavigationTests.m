#import "ReaderNavigation.h"

static int failures;
static void Check(BOOL ok, const char *message) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", message);
    if (!ok) failures++;
}

int main(void) { @autoreleasepool {
    NSMutableIndexSet *bookmarks = [NSMutableIndexSet indexSetWithIndex:4];
    [bookmarks addIndex:0];
    [bookmarks addIndex:50000]; // Stale index in a sidecar.
    NSMutableIndexSet *annotations = [NSMutableIndexSet indexSetWithIndex:4];
    [annotations addIndex:2];
    Check([PDFSavedPageRows(bookmarks, annotations, PDFSavedPageFilterAll, 5) isEqual:@[@0, @2, @4]],
          "all saved pages are sorted, unique and in bounds");
    Check([PDFSavedPageRows(bookmarks, annotations, PDFSavedPageFilterBookmarks, 5) isEqual:@[@0, @4]],
          "bookmark filter includes shared pages but excludes annotation-only pages");
    Check([PDFSavedPageRows(bookmarks, annotations, PDFSavedPageFilterAnnotations, 5) isEqual:@[@2, @4]],
          "annotated filter includes shared pages but excludes bookmark-only pages");
    Check(PDFSavedPageRows(bookmarks, annotations, PDFSavedPageFilterAll, 0).count == 0,
          "zero-page document has no saved rows");
    Check(PDFSavedPageRows([NSIndexSet indexSet], annotations, PDFSavedPageFilterBookmarks, 5).count == 0,
          "empty filter does not fall back to all saved pages");

    NSMutableArray *history = [NSMutableArray array];
    PDFRecordPageJump(history, -1, 2, 5);
    PDFRecordPageJump(history, 1, 5, 5);
    PDFRecordPageJump(history, 2, 2, 5);
    Check(PDFJumpBackIndex(history, 2) == NSNotFound, "same-page and invalid jumps create no history");
    PDFRecordPageJump(history, 0, 2, 5);
    PDFRecordPageJump(history, 0, 3, 5);
    PDFRecordPageJump(history, 3, 4, 5);
    Check([history isEqual:@[@0, @3]], "history stores origin pages without consecutive duplicates");
    Check(PDFJumpBackIndex(history, 4) == 1 && PDFJumpBackIndex(history, 3) == 0,
          "jump back picks the latest different page, even after a manual scroll");
    [history removeAllObjects];
    for (NSInteger p = 0; p < 25; p++) PDFRecordPageJump(history, p, p + 1, 26);
    Check(history.count == 16 && [history.firstObject integerValue] == 9 && [history.lastObject integerValue] == 24,
          "only the newest 16 origins are retained");
    Check(PDFPageJumpOffset(900, 200, 1000, 2500, 78) == 500,
          "jump back centers a short slide instead of the following page");
    Check(PDFPageJumpOffset(900, 1500, 1000, 2500, 78) == 822,
          "tall pages still open at their top below the dock");
    Check(PDFPageJumpOffset(80, 100, 1000, 2500, 18) == 0 &&
          PDFPageJumpOffset(2300, 100, 1000, 2500, 18) == 1500 &&
          PDFPageJumpOffset(80, 100, 1000, 242, 78) == 0, "jump offsets respect both document edges");
    PDFReadingAnchor slide = {6, 0.5, PDFReadingReferenceForViewport(500, 1000, 2500, 900, 200)};
    Check(slide.reference == PDFReadingSlideCenter && PDFRestoreReadingOffset(slide, 1500, 320, 720, 4000) == 1300,
          "a centered short slide stays centered after rotation");
    PDFReadingAnchor shifted = {6, 0.625, PDFReadingReferenceForViewport(525, 1000, 2500, 900, 200)};
    Check(shifted.reference == PDFReadingSlideCenter && PDFRestoreReadingOffset(shifted, 1500, 320, 720, 4000) == 1340,
          "a small scroll on a short slide preserves the point under the viewport center");
    PDFReadingAnchor topLine = {5, 0.9, PDFReadingReferenceForViewport(1800, 1000, 5000, 2000, 2000)};
    Check(topLine.reference == PDFReadingTopLine && PDFRestoreReadingOffset(topLine, 0, 3000, 720, 6000) == 2700,
          "across a tall page break relayout follows the top line, not the next page");
    PDFReadingAnchor start = {0, 0, PDFReadingReferenceForViewport(0, 1000, 2500, 80, 840)};
    PDFReadingAnchor end = {2, 0, PDFReadingReferenceForViewport(1500, 1000, 2500, 1600, 840)};
    Check(start.reference == PDFReadingDocumentStart && PDFRestoreReadingOffset(start, 80, 1200, 720, 4000) == 0 &&
          end.reference == PDFReadingDocumentEnd && PDFRestoreReadingOffset(end, 2700, 1200, 720, 4000) == 3280,
          "rotation keeps the document start and end pinned when short pages grow");
    return failures ? 1 : 0;
}}
