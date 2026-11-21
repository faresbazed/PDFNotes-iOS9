#import "Models.h"
#include <stdio.h>
#include <stdlib.h>

// Only persistence is disabled; all note ownership and undo logic is production code.
@interface MemoryStore : AnnotationStore
@end
@implementation MemoryStore
- (void)loadFromDisk {}
- (void)markDirty {}
@end

@interface PDFNoteBadgeView : NSObject
@property (strong) TextNote *note;
@property CGRect frame;
@end
@implementation PDFNoteBadgeView
@end

enum { UIGestureRecognizerStateChanged, UIGestureRecognizerStateEnded, UIGestureRecognizerStateCancelled };
@interface UIPanGestureRecognizer : NSObject
@property (strong) id view;
@property NSInteger state;
@property CGPoint translation;
- (CGPoint)translationInView:(id)view;
- (void)setTranslation:(CGPoint)p inView:(id)view;
@end
@implementation UIPanGestureRecognizer
- (CGPoint)translationInView:(id)view { return self.translation; }
- (void)setTranslation:(CGPoint)p inView:(id)view { self.translation = p; }
@end

@protocol TestDelegate
- (void)pageViewDidChangeAnnotations:(id)view;
@end

static CGFloat PDFClamp(CGFloat v, CGFloat lo, CGFloat hi) { return MAX(lo, MIN(v, hi)); }
@interface PageView : NSObject {
    AnnotationStore *_store;
    NSInteger _pageIndex;
}
@property CGRect bounds;
@property (weak) id<TestDelegate> delegate;
- (instancetype)initWithStore:(AnnotationStore *)store;
- (CGPoint)normalisedPointForViewPoint:(CGPoint)p;
- (void)noteBadgePanned:(UIPanGestureRecognizer *)gr;
@end
@implementation PageView
- (instancetype)initWithStore:(AnnotationStore *)store {
    if ((self = [super init])) { _store = store; _pageIndex = 2; self.bounds = CGRectMake(0, 0, 1000, 1000); }
    return self;
}
- (CGPoint)normalisedPointForViewPoint:(CGPoint)p {
    return CGPointMake(p.x / self.bounds.size.width, p.y / self.bounds.size.height);
}
// Extracted unmodified at build time so the regression covers the actual caller.
#include "noteBadgePanned.inc"
@end

static void check(BOOL ok, const char *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static void checkPosition(AnnotationStore *store, CGPoint expected, const char *message) {
    CGPoint actual = [store notesForPage:2].firstObject.normalizedPosition;
    if (fabs(actual.x - expected.x) > 0.00001 || fabs(actual.y - expected.y) > 0.00001) {
        fprintf(stderr, "FAIL: %s: expected (%.2f, %.2f), got (%.2f, %.2f)\n",
                message, expected.x, expected.y, actual.x, actual.y);
        exit(1);
    }
}
static MemoryStore *storeWithNote(void) {
    MemoryStore *store = [[MemoryStore alloc] initWithPDFPath:@"drag-undo-test.pdf"];
    TextNote *note = [TextNote new];
    note.normalizedPosition = CGPointMake(0.2, 0.3);
    [store saveNote:note onPage:2];
    return store;
}
static void testDrag(NSInteger finalState) {
    MemoryStore *store = storeWithNote();
    PageView *page = [[PageView alloc] initWithStore:store];
    PDFNoteBadgeView *badge = [PDFNoteBadgeView new];
    badge.note = [store notesForPage:2].firstObject;
    badge.frame = CGRectMake(200, 300, 100, 100);
    UIPanGestureRecognizer *pan = [UIPanGestureRecognizer new];
    pan.view = badge;
    pan.state = UIGestureRecognizerStateChanged;
    pan.translation = CGPointMake(200, 100);
    [page noteBadgePanned:pan];
    checkPosition(store, CGPointMake(0.2, 0.3), "drag preview must not mutate store");
    pan.state = finalState;
    pan.translation = CGPointMake(200, 300);
    [page noteBadgePanned:pan];
    checkPosition(store, CGPointMake(0.6, 0.7), "drag commits position");
    check([store undoReturningPage] == 2, "undo returns affected page");
    checkPosition(store, CGPointMake(0.2, 0.3), "undo drag restores original position");
    check([store redoReturningPage] == 2, "redo returns affected page");
    checkPosition(store, CGPointMake(0.6, 0.7), "redo drag restores moved position");
    [store undoReturningPage];
    [store undoReturningPage];
    check([store notesForPage:2].count == 0, "one undo entry per drag");
}
int main(void) {
    @autoreleasepool {
        MemoryStore *empty = [[MemoryStore alloc] initWithPDFPath:@"empty.pdf"];
        [empty moveNoteWithID:@"missing" toNormalizedPosition:CGPointZero onPage:2 recordUndo:YES];
        check(!empty.canUndo && [empty undoReturningPage] == NSNotFound, "empty page move is a no-op");
        MemoryStore *store = storeWithNote();
        NSString *identifier = [store notesForPage:2].firstObject.identifier;
        [store moveNoteWithID:identifier toNormalizedPosition:CGPointMake(0.6, 0.7) onPage:2 recordUndo:YES];
        [store undoReturningPage];
        checkPosition(store, CGPointMake(0.2, 0.3), "direct store move undo control");
        puts("PASS: direct store move undo (control)");
        [store moveNoteWithID:@"missing" toNormalizedPosition:CGPointZero onPage:2 recordUndo:YES];
        checkPosition(store, CGPointMake(0.2, 0.3), "unknown note move is a no-op");
        check(store.canRedo, "unknown note must not change history");
        [store moveNoteWithID:identifier toNormalizedPosition:CGPointMake(NAN, INFINITY) onPage:2 recordUndo:YES];
        checkPosition(store, CGPointMake(0.15, 0.15), "nonfinite positions use safe defaults");
        [store undoReturningPage];
        checkPosition(store, CGPointMake(0.2, 0.3), "invalid position move remains undoable");
        puts("PASS: empty, unknown-note and invalid-position moves");
        testDrag(UIGestureRecognizerStateEnded);
        puts("PASS: ended drag preview, commit, undo, redo and history");
        testDrag(UIGestureRecognizerStateCancelled);
        puts("PASS: cancelled drag commit, undo and redo");
    }
    return 0;
}
