// Linux call-recording doubles; PageView owns all smoothing and publication decisions.
#import <Foundation/Foundation.h>
#include <assert.h>
#include <math.h>

typedef NSPoint CGPoint;
typedef NSRect CGRect;
#define CGPointMake NSMakePoint
#define CGRectNull NSMakeRect(INFINITY, INFINITY, 0, 0)
#define CGRectIsNull(r) isinf((r).origin.x)
#define CGRectUnion(a,b) (CGRectIsNull(a) ? (b) : NSUnionRect((a),(b)))
#define CGRectGetMidX NSMidX
#define CGRectGetMidY NSMidY
#define CGRectInset NSInsetRect
#define CGRectIntegral NSIntegralRect
#define CGRectIsEmpty NSIsEmptyRect

// A command's last point is its endpoint; quadratics also carry a control.
typedef NSArray *CGPathRef;
typedef NSMutableArray *CGMutablePathRef;
#define CGPathCreateMutable() [NSMutableArray new]
#define CGPathCreateMutableCopy(p) [(p) mutableCopy]
#define CGPathRelease(p) [(p) release]
static NSValue *point(CGFloat x, CGFloat y) { return [NSValue valueWithPoint:NSMakePoint(x,y)]; }
#define CGPathMoveToPoint(p,t,x,y) [(p) addObject:@[[NSNull null],point(x,y)]]
#define CGPathAddLineToPoint(p,t,x,y) [(p) addObject:@[point(x,y)]]
#define CGPathAddQuadCurveToPoint(p,t,cx,cy,x,y) [(p) addObject:@[point(cx,cy),point(x,y)]]
static CGRect CGPathGetBoundingBox(CGPathRef path) {
    CGFloat xmin = INFINITY, xmax = -INFINITY, ymin = INFINITY, ymax = -INFINITY;
    for (NSArray *command in path) for (id value in command) {
        if (value == [NSNull null]) continue;
        CGPoint p = [value pointValue];
        xmin = MIN(xmin,p.x); xmax = MAX(xmax,p.x);
        ymin = MIN(ymin,p.y); ymax = MAX(ymax,p.y);
    }
    return path.count ? NSMakeRect(xmin,ymin,xmax-xmin,ymax-ymin) : CGRectNull;
}

typedef NSNumber UIColor;
@interface NSNumber (Color)
+ (instancetype)blackColor;
- (instancetype)colorWithAlphaComponent:(CGFloat)a;
- (NSNumber *)CGColor;
@end
@implementation NSNumber (Color)
+ (instancetype)blackColor { return @1; }
- (instancetype)colorWithAlphaComponent:(CGFloat)a { return @(a); }
- (NSNumber *)CGColor { return self; }
@end

enum { kCALineCapRound, kCALineJoinRound };
static NSUInteger publications;
@interface CALayer : NSObject {
    CGRect bounds; CGPoint position; BOOL allowsGroupOpacity;
    CGFloat opacity, lineWidth, contentsScale; int lineCap, lineJoin;
    id strokeColor, fillColor; CGPathRef path; NSMutableArray *sublayers;
}
@property CGRect bounds;
@property CGPoint position;
@property BOOL allowsGroupOpacity;
@property CGFloat opacity, lineWidth, contentsScale;
@property int lineCap, lineJoin;
@property (retain) id strokeColor, fillColor;
@property (nonatomic, copy) CGPathRef path;
@property (readonly) NSMutableArray *sublayers;
@end
@implementation CALayer
@synthesize bounds, position, allowsGroupOpacity, opacity, lineWidth, contentsScale;
@synthesize lineCap, lineJoin, strokeColor, fillColor, sublayers, path;
+ (instancetype)layer {
    CALayer *l = [[[self alloc] init] autorelease];
    l->sublayers = [NSMutableArray new]; l.opacity = 1; return l;
}
- (void)setPath:(CGPathRef)p {
    assert(p.count <= 34 && "republished more than one 32-sample segment plus endpoints");
    [path release]; path = [p copy]; publications++;
}
- (void)addSublayer:(CALayer *)l { [sublayers addObject:l]; }
- (void)insertSublayer:(CALayer *)l below:(CALayer *)other { [self addSublayer:l]; }
@end
typedef CALayer CAShapeLayer;
#include "constants.inc"

@interface CATransaction : NSObject @end
@implementation CATransaction
+ (void)begin {}
+ (void)setDisableActions:(BOOL)disable {}
+ (void)commit {}
@end

typedef NSValue UITouch;
@interface NSValue (Touch)
- (CGPoint)locationInView:(id)view;
@end
@implementation NSValue (Touch)
- (CGPoint)locationInView:(id)view { return self.pointValue; }
@end
typedef NSArray UIEvent;
@interface NSArray (CoalescedEvent)
- (NSSet *)touchesForView:(id)view;
- (NSArray *)coalescedTouchesForTouch:(UITouch *)touch;
@end
@implementation NSArray (CoalescedEvent)
- (NSSet *)touchesForView:(id)view { return nil; } // No other finger.
- (NSArray *)coalescedTouchesForTouch:(UITouch *)touch { return self; }
@end

enum { ReaderToolPen, ReaderToolMarker, ReaderToolEraser, ReaderToolNote };
enum { StrokeKindPen, StrokeKindMarker, PDFReadingThemeNight };
@interface Stroke : NSObject { int kind; UIColor *color; CGFloat widthFraction; NSMutableArray *points; }
@property int kind;
@property (retain) UIColor *color;
@property CGFloat widthFraction;
@property (readonly) CGFloat alpha;
@property (readonly) NSMutableArray *points;
@end
@implementation Stroke
@synthesize kind, color, widthFraction, points;
- (CGFloat)alpha { return kind == StrokeKindPen ? 1 : 0.3f; }
- (void)addNormalizedPoint:(CGPoint)p {
    if (!points) points = [NSMutableArray new];
    [points addObject:point(p.x,p.y)];
}
@end

// Unused branches stay in the compiled touch handlers.
@interface NSObject (UnusedUI)
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)pageViewDidInteract:(id)view;
- (void)pageViewDidBeginDrawing:(id)view;
- (void)cancelActiveTouchIfNeeded;
- (void)updateEraserRingAtPoint:(CGPoint)p visible:(BOOL)visible;
- (BOOL)stageEraseAlongSegmentFrom:(CGPoint)a to:(CGPoint)b;
- (void)invalidateInkBitmap;
- (void)updateSnappedStraightLineToViewPoint:(CGPoint)p;
@end
@interface PageView : NSObject {
@public
    int _tool, _theme; CGFloat _inkZoomScale, _penWidthFraction, _markerWidthFraction, _maxMoveDistance;
    CALayer *_liveLayer, *_liveContainer, *_eraserRingLayer, *layer;
    CGRect _frozenInkBounds;
    CGMutablePathRef _liveCGPath;
    CGPoint _touchStartViewPt, _lastTouchViewPt, _prevLiveViewPt, _lastSmoothedMidPt;
    NSUInteger _segmentPointCount, _livePointCount;
    UITouch *_activeTouch; NSTimeInterval _touchStartTime;
    BOOL _snappedToStraightLine, _eraserMovedEnough;
    Stroke *_currentStroke; UIColor *_drawColor; NSMutableIndexSet *_stagedErasedIndices;
}
@property (readonly) CGRect bounds;
@property (readonly) CALayer *layer;
@property (readonly) id delegate;
@end
@implementation PageView
@synthesize layer;
- (CGRect)bounds { return NSMakeRect(0,0,2000,2000); }
- (id)delegate { return nil; }
- (CGPoint)normalisedPointForViewPoint:(CGPoint)p { return p; }
- (CGFloat)viewWidthForFraction:(CGFloat)fraction inSize:(NSSize)s { return 4; }
- (void)scheduleStraightLineSnapCheck:(CGPoint)p {}
#include "touch.inc"
@end

static NSValue *sample(NSUInteger i) { return point(10 + 2*i, 100 + i%7); }

static void testStroke(int tool, BOOL night) {
    PageView *page = [PageView new];
    page->_inkZoomScale = 1; page->_tool = tool;
    page->_theme = night ? PDFReadingThemeNight : 0;
    page->_drawColor = @0.25; // Detect applying source alpha as well as group opacity.
    page->layer = [CALayer layer];
    NSSet *touch = [NSSet setWithObject:sample(0)];
    [page touchesBegan:touch withEvent:@[]];
    CALayer *group = page.layer.sublayers.lastObject;
    assert(group.allowsGroupOpacity);
    assert(fabs(group.opacity - (night ? 0.44f : page->_currentStroke.alpha)) < 1e-6);

    // Individual callbacks, a batch ending exactly at a freeze, then one
    // event spanning many segments. Validate even the boundary-only preview.
    NSUInteger cursor = 0;
    for (NSNumber *length in @[@1, @1, @29, @513, @1]) {
        NSMutableArray *batch = [NSMutableArray array];
        for (NSUInteger i = 0; i < length.unsignedIntegerValue; i++)
            [batch addObject:sample(++cursor)];
        NSUInteger before = publications, oldLayers = group.sublayers.count;
        [page touchesMoved:touch withEvent:batch];
        assert(publications - before == group.sublayers.count - oldLayers + 1);
        assert(publications - before <= (batch.count + 31)/32 + 1);
        assert(NSEqualPoints(group.position, NSMakePoint(NSMidX(group.bounds), NSMidY(group.bounds))));

        // Flatten the published segments (each starts at the preceding end).
        NSMutableArray *commands = [NSMutableArray array];
        for (CALayer *segment in group.sublayers) {
            assert(segment.opacity == 1 && [segment.strokeColor doubleValue] == 1);
            assert(NSContainsRect(group.bounds, segment.bounds));
            assert(NSEqualPoints(segment.position, NSMakePoint(NSMidX(segment.bounds), NSMidY(segment.bounds))));
            id start = commands.count ? [commands.lastObject lastObject] : sample(0);
            assert(([segment.path.firstObject isEqual:@[[NSNull null], start]]));
            [commands addObjectsFromArray:[segment.path subarrayWithRange:NSMakeRange(1,segment.path.count-1)]];
        }
        assert([commands.firstObject isEqual:@[point(11, 100.5)]]);
        assert([commands.lastObject isEqual:@[batch.lastObject]]);
        assert(NSPointInRect([batch.lastObject pointValue], group.bounds));
        if (cursor == 1) assert(group.bounds.size.width < 12 && group.bounds.size.height < 12);

        // One smoothed command per accepted sample plus ONLY the current tip.
        assert(commands.count == cursor + 1);
        for (NSUInteger i = 1; i < cursor; i++) {
            NSArray *quad = [commands objectAtIndex:i];
            assert(quad.count == 2 && [quad.firstObject isEqual:sample(i)]);
        }
        assert(![[page->_liveCGPath.lastObject lastObject] isEqual:batch.lastObject]);
    }
    NSValue *end = sample(cursor + 1);
    [page finishLivePathAtPoint:end.pointValue];
    assert([[page->_liveLayer.path.lastObject lastObject] isEqual:end]);
    assert(page->_currentStroke.points.count == cursor + 2);
    assert([page->_currentStroke.points.lastObject isEqual:end]);
}
static void testWithoutMovedCallback(NSUInteger endIndex) {
    PageView *page = [PageView new];
    page->_tool = ReaderToolPen;
    [page touchesBegan:[NSSet setWithObject:sample(0)] withEvent:@[]];
    [page finishLivePathAtPoint:[sample(endIndex) pointValue]];
    if (endIndex == 0) {
        assert(page->_currentStroke.points.count == 1); // A true tap remains a dot.
    } else {
        assert(([page->_currentStroke.points isEqual:@[sample(0), sample(endIndex)]]));
        assert([page->_liveLayer.path.lastObject isEqual:@[sample(endIndex)]]);
    }
}
int main(void) {
    @autoreleasepool {
        testStroke(ReaderToolPen, NO);
        testStroke(ReaderToolMarker, NO);
        testStroke(ReaderToolMarker, YES);
        testWithoutMovedCallback(0);
        testWithoutMovedCallback(10);
        puts("PASS: latest tip, bounded pen/marker segments, marker grouping, taps and quick dashes");
    }
    return 0;
}
