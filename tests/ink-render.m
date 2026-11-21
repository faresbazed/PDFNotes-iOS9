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
        puts("PASS: ink render ordering, coalescing, erase/cancel, release, resize and allocation retry");
    }
    return 0;
}
