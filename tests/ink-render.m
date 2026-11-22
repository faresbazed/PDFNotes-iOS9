// Exercise PageView's production scheduler with stroke IDs in place of pixels.
#import <Foundation/Foundation.h>
#include <assert.h>

typedef NSRect CGRect;
typedef NSSize CGSize;
typedef NSInteger PDFReadingTheme;
typedef NSString Stroke;
typedef NSArray UIImage;
#define CGSizeEqualToSize NSEqualSizes

@interface PDFCancelToken : NSObject { BOOL _cancelled; }
- (BOOL)isCancelled;
- (void)cancel;
@end
@implementation PDFCancelToken
- (BOOL)isCancelled { return _cancelled; }
- (void)cancel { _cancelled = YES; }
@end

@interface Surface : NSObject { UIImage *_image; }
@property (retain) UIImage *image;
- (void)removeFromSuperlayer;
@end
@implementation Surface
@synthesize image = _image;
- (void)removeFromSuperlayer {}
@end

@interface CATransaction : NSObject
@end
@implementation CATransaction
+ (void)begin {}
+ (void)setDisableActions:(BOOL)disable {}
+ (void)commit {}
@end

@interface PDFDoc : NSObject
@end
@implementation PDFDoc
+ (int)renderQueue { return 1; }
@end

@interface PDFWeakTimerTarget : NSObject
@end
@implementation PDFWeakTimerTarget
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)delay target:(id)target
                                   selector:(SEL)sel repeats:(BOOL)repeats {
    return [NSTimer timerWithTimeInterval:delay target:target selector:sel userInfo:nil repeats:repeats];
}
@end

static void (*beforePublish)(void);
static int queue, jobs, replayed;
static BOOL failAllocation;
static int dispatch_get_main_queue(void) { return 0; }
static void dispatch_async(int target, void (^job)(void)) {
    int old = queue;
    queue = target;
    if (!target && beforePublish) {
        void (*edit)(void) = beforePublish;
        beforePublish = NULL;
        edit();
    }
    job();
    queue = old;
}
static UIImage *PDFRenderInkBitmap(CGSize sz, CGFloat scale, CGRect trim, PDFReadingTheme theme,
                                   UIImage *base, NSArray *strokes, PDFCancelToken *token) {
    assert(queue == 1);
    jobs++;
    replayed += strokes.count;
    return failAllocation ? nil : [(base ?: @[]) arrayByAddingObjectsFromArray:strokes];
}

@interface PageView : NSObject {
@public
    NSMutableArray *_strokes, *_pendingInkLayers;
    NSMutableIndexSet *_stagedErasedIndices;
    NSUInteger _bakedStrokeCount;
    CGSize _inkTargetSize;
    CGFloat _inkTargetScale, _inkZoomScale, _renderedPixelWidth;
    PDFReadingTheme _theme;
    PDFCancelToken *_inkRenderToken, *_pdfRenderToken;
    NSTimer *_inkBatchTimer;
    Stroke *_currentStroke;
    Surface *_inkImageView, *_imageView;
    CGRect _bounds;
}
@property CGRect bounds;
@end
@implementation PageView
@synthesize bounds = _bounds;
- (instancetype)init {
    if ((self = [super init])) {
        _strokes = [NSMutableArray new];
        _pendingInkLayers = [NSMutableArray new];
        _stagedErasedIndices = [NSMutableIndexSet new];
        _inkImageView = [Surface new];
        _bounds = NSMakeRect(0, 0, 100, 100);
        _inkZoomScale = 1;
    }
    return self;
}
- (CGFloat)inkBitmapScaleForZoom:(CGFloat)zoom { return zoom; }
- (CGRect)safeTrim { return NSMakeRect(0, 0, 1, 1); }
- (void)cancelActiveTouchIfNeeded {}
#include "scheduler.inc"
- (void)append:(NSString *)stroke {
    [_strokes addObject:stroke];
    [_pendingInkLayers addObject:[Surface new]];
    [self scheduleInkRender];
}
- (void)penLift:(NSString *)stroke {
    [_strokes addObject:stroke];
    [_pendingInkLayers addObject:[Surface new]];
    [self batchFinishedInk];
}
@end

static PageView *page;
static void appendDuringRender(void) {
    [page append:@"B"];
    [page append:@"C"];
    assert(page->_pendingInkLayers.count == 3 && jobs == 1);
}
static void stageErase(void) {
    [page->_stagedErasedIndices addIndex:1];
    [page invalidateInkBitmap];
}
static void cancelErase(void) {
    [page->_stagedErasedIndices removeAllIndexes];
    [page invalidateInkBitmap];
}
static void clearPage(void) {
    [page->_strokes removeAllObjects];
    [page invalidateInkBitmap];
}
static void releasePage(void) { [page releaseContent]; }
static void resizePage(void) { page.bounds = NSMakeRect(0, 0, 120, 120); }

int main(void) {
    @autoreleasepool {
        page = [PageView new];
        beforePublish = appendDuringRender;
        [page append:@"A"];
        assert(jobs == 2 && replayed == 3 && page->_pendingInkLayers.count == 0);
        assert(([page->_inkImageView.image isEqual:@[@"A", @"B", @"C"]]));

        beforePublish = stageErase;
        [page append:@"D"];
        assert(([page->_inkImageView.image isEqual:@[@"A", @"C", @"D"]]));
        beforePublish = cancelErase;
        [page invalidateInkBitmap];
        assert(([page->_inkImageView.image isEqual:@[@"A", @"B", @"C", @"D"]]));

        beforePublish = clearPage;
        [page append:@"E"];
        assert(!page->_inkImageView.image && !page->_pendingInkLayers.count);
        beforePublish = releasePage;
        [page append:@"F"];
        assert(!page->_inkImageView.image && !page->_pendingInkLayers.count && !page->_inkRenderToken);
        int before = jobs;
        beforePublish = resizePage;
        [page scheduleInkRender];
        assert(jobs == before + 2 && [page->_inkImageView.image isEqual:@[@"F"]]);

        failAllocation = YES;
        [page append:@"G"];
        assert([page->_inkImageView.image isEqual:@[@"F"]] && page->_pendingInkLayers.count == 1);
        failAllocation = NO;
        [page scheduleInkRender];
        assert(([page->_inkImageView.image isEqual:@[@"F", @"G"]] && !page->_pendingInkLayers.count));
        page = [PageView new];
        before = jobs;
        for (int i = 0; i < 32; i++) {
            [page penLift:[NSString stringWithFormat:@"%d", i]];
            assert(page->_pendingInkLayers.count == (i + 1) % 8);
        }
        assert(jobs == before + 4 && [page->_inkImageView.image isEqual:page->_strokes]);

        [page penLift:@"a"];
        NSTimer *timer = page->_inkBatchTimer;
        [page penLift:@"b"];
        assert(timer && timer == page->_inkBatchTimer);
        page->_currentStroke = @"c";
        [timer fire];
        assert(!page->_inkBatchTimer && page->_pendingInkLayers.count == 2 && jobs == before + 4);
        page->_currentStroke = nil;
        [page penLift:@"c"];
        [page->_inkBatchTimer fire];
        assert(!page->_inkBatchTimer && !page->_pendingInkLayers.count && jobs == before + 5);
        assert([page->_inkImageView.image isEqual:page->_strokes]);
        [page penLift:@"evict"];
        timer = page->_inkBatchTimer;
        [page releaseContent];
        [page inkBatchTimerFired:timer];
        assert(!page->_inkBatchTimer && jobs == before + 5 && !page->_inkImageView.image);
        puts("PASS: 32 rapid pen lifts, 4 bitmap jobs; idle flush, active stroke and eviction");
        puts("PASS: ink render ordering, coalescing, erase/cancel, release, resize and allocation retry");
    }
    return 0;
}
