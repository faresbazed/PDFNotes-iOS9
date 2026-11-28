#import <Foundation/Foundation.h>

// UIKit-free payload: points identify each stroke and survive copying.
static NSUInteger strokeCopies;
@interface Stroke : NSObject <NSCopying> {
    NSArray *_points;
}
@property (nonatomic, retain) NSArray *points;
@end
@implementation Stroke
@synthesize points = _points;
- (id)copyWithZone:(NSZone *)zone {
    strokeCopies++;
    Stroke *copy = [[[self class] allocWithZone:zone] init];
    copy.points = [self.points copy];
    return copy;
}
@end
typedef NSObject TextNote;
enum { PDFEditAllPages = -1 };

@interface PDFPageEditAction : NSObject {
    NSInteger _pageIndex;
    Stroke *_appendedStroke;
    NSArray *_beforeStrokes, *_afterStrokes, *_beforeNotes, *_afterNotes;
    NSMutableDictionary *_documentStrokes, *_documentNotes;
}
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, retain) Stroke *appendedStroke;
@property (nonatomic, retain) NSArray *beforeStrokes;
@property (nonatomic, retain) NSArray *afterStrokes;
@property (nonatomic, retain) NSArray *beforeNotes;
@property (nonatomic, retain) NSArray *afterNotes;
@property (nonatomic, retain) NSMutableDictionary *documentStrokes;
@property (nonatomic, retain) NSMutableDictionary *documentNotes;
@end
@implementation PDFPageEditAction
@synthesize documentStrokes = _documentStrokes, documentNotes = _documentNotes;
@synthesize appendedStroke = _appendedStroke;
@synthesize pageIndex = _pageIndex, beforeStrokes = _beforeStrokes;
@synthesize afterStrokes = _afterStrokes, beforeNotes = _beforeNotes, afterNotes = _afterNotes;
@end

static const NSUInteger kMaxUndoSteps = 45;
@interface AnnotationStore : NSObject {
    NSMutableDictionary *_strokesByPage, *_notesByPage;
    NSMutableArray *_undoStack, *_redoStack;
}
@end
@implementation AnnotationStore
- (id)init {
    if ((self = [super init])) {
        _strokesByPage = [NSMutableDictionary new];
        _notesByPage = [NSMutableDictionary new];
        _undoStack = [NSMutableArray new];
        _redoStack = [NSMutableArray new];
    }
    return self;
}
- (void)markDirty {}
// MODEL_METHODS
@end

static int failures;
static void Check(BOOL ok, const char *name) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok) failures++;
}
static Stroke *MakeStroke(NSString *name) {
    Stroke *stroke = [Stroke new];
    stroke.points = @[name];
    return stroke;
}
static BOOL HasStrokes(AnnotationStore *store, NSArray *names) {
    NSMutableArray *actual = [NSMutableArray array];
    for (Stroke *stroke in [store strokesForPage:0]) {
        [actual addObject:[stroke.points firstObject]];
    }
    return [actual isEqualToArray:names];
}
int main(void) {
    @autoreleasepool {
        AnnotationStore *store = [AnnotationStore new];
        Stroke *a = MakeStroke(@"A"), *b = MakeStroke(@"B");
        Check([store undoReturningPage] == NSNotFound && ![store canUndo], "empty undo is a no-op");
        Check([store redoReturningPage] == NSNotFound && ![store canRedo], "empty redo is a no-op");
        [store addStroke:nil onPage:0];
        [store addStroke:[Stroke new] onPage:0];
        Check(![store canUndo] && HasStrokes(store, @[]), "nil and empty strokes are ignored");
        [store addStroke:a onPage:0];
        [store addStroke:b onPage:0];
        Check(HasStrokes(store, @[@"A", @"B"]), "add A then B");
        Check([store undoReturningPage] == 0 && HasStrokes(store, @[@"A"]), "undo B leaves exactly A");
        Check([store undoReturningPage] == 0 && HasStrokes(store, @[]), "undo A leaves no strokes");
        Check([store redoReturningPage] == 0 && HasStrokes(store, @[@"A"]), "redo A");
        Check([store redoReturningPage] == 0 && HasStrokes(store, @[@"A", @"B"]), "redo B");
        [store replaceStrokes:@[b] onPage:0];
        Check(HasStrokes(store, @[@"B"]), "erase by replacing strokes");
        Check([store undoReturningPage] == 0 && HasStrokes(store, @[@"A", @"B"]), "undo erase restores A and B");
        [store clearPage:0];
        Check(HasStrokes(store, @[]), "clear page");
        Check([store undoReturningPage] == 0 && HasStrokes(store, @[@"A", @"B"]), "undo clear restores A and B");
        [store addStroke:MakeStroke(@"C") onPage:1];
        Check([store undoReturningPage] == 1 && [[store strokesForPage:1] count] == 0
              && HasStrokes(store, @[@"A", @"B"]), "undo is page-specific");
        Check([store canRedo], "undo enables redo");
        [store addStroke:a onPage:1];
        Check(![store canRedo], "new edit discards redo");
        NSUInteger beforeClear = strokeCopies;
        [store clearAllAnnotations];
        Check(!store.hasAnnotations && [store undoReturningPage] == PDFEditAllPages &&
              [store strokesForPage:0].count == 2 && [store strokesForPage:1].count == 1 &&
              [store redoReturningPage] == PDFEditAllPages && !store.hasAnnotations &&
              strokeCopies == beforeClear, "document clear, Undo and Redo never copy stroke geometry");
        AnnotationStore *dense = [AnnotationStore new];
        strokeCopies = 0;
        for (NSUInteger i = 0; i < 256; i++) {
            [dense addStroke:a onPage:0];
        }
        printf("256 pen lifts: %lu stroke copies\n", (unsigned long)strokeCopies);
        Check(strokeCopies <= 512, "append does not copy older strokes");
        a.points = @[@"changed input"];
        ((Stroke *)[dense strokesForPage:0].lastObject).points = @[@"changed store"];
        for (NSUInteger i = 0; i < kMaxUndoSteps; i++) [dense undoReturningPage];
        Check(!dense.canUndo && [dense strokesForPage:0].count == 256 - kMaxUndoSteps,
              "dense page preserves bounded undo history");
        for (NSUInteger i = 0; i < kMaxUndoSteps; i++) [dense redoReturningPage];
        Check(!dense.canRedo && [dense strokesForPage:0].count == 256 &&
              [[((Stroke *)[dense strokesForPage:0].lastObject).points firstObject] isEqual:@"A"],
              "redo keeps a private copy of committed ink");
        printf("%s: stroke undo regression (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    }
    return failures ? 1 : 0;
}
