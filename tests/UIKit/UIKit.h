#import <Foundation/Foundation.h>
#include <math.h>

typedef NSPoint CGPoint;
typedef NSSize CGSize;
typedef NSRect CGRect;
#define CGPointMake NSMakePoint
#define CGSizeMake NSMakeSize
#define CGRectMake NSMakeRect
#define CGPointZero NSZeroPoint
#define CGRectNull NSMakeRect(INFINITY, INFINITY, 0, 0)
#define CGRectIsNull(r) isinf((r).origin.x)
#define CGRectUnion NSUnionRect
typedef const void *CGColorRef;
static inline size_t CGColorGetNumberOfComponents(CGColorRef c) { return 0; }
static inline const CGFloat *CGColorGetComponents(CGColorRef c) { return NULL; }
enum { kCGLineCapRound, kCGLineJoinRound };
#define UIApplicationWillResignActiveNotification @"test.resign"
#define UIApplicationDidEnterBackgroundNotification @"test.background"
#define UIApplicationWillTerminateNotification @"test.terminate"

@interface NSOperationQueue (TestQoS)
- (void)setQualityOfService:(NSQualityOfService)quality;
@end

@interface UIColor : NSObject
@property CGFloat r, g, b, a;
@property (readonly) CGColorRef CGColor;
+ (instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (instancetype)blackColor;
- (BOOL)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a;
- (BOOL)getWhite:(CGFloat *)w alpha:(CGFloat *)a;
@end

@interface NSValue (TestGeometry)
+ (instancetype)valueWithCGPoint:(CGPoint)p;
- (CGPoint)CGPointValue;
@end

@interface UIBezierPath : NSObject
@property NSInteger lineCapStyle, lineJoinStyle;
@property CGFloat lineWidth;
+ (instancetype)bezierPath;
- (void)moveToPoint:(CGPoint)p;
- (void)addLineToPoint:(CGPoint)p;
- (void)addQuadCurveToPoint:(CGPoint)p controlPoint:(CGPoint)c;
@end
