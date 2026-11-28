#import <UIKit/UIKit.h>

@implementation UIApplication {
    NSMutableDictionary *_tasks;
    NSUInteger _nextTask;
}
+ (instancetype)sharedApplication {
    static UIApplication *app;
    @synchronized (self) { if (!app) app = [self new]; }
    return app;
}
- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithName:(NSString *)name expirationHandler:(void (^)(void))handler {
    @synchronized (self) {
        if (self.testDenyTasks) return UIBackgroundTaskInvalid;
        if (!_tasks) _tasks = [NSMutableDictionary dictionary];
        _tasks[@(++_nextTask)] = [handler copy];
        return _nextTask;
    }
}
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)task {
    @synchronized (self) {
        NSCAssert(_tasks[@(task)], @"Background task ended twice or invalid");
        [_tasks removeObjectForKey:@(task)];
    }
}
- (NSUInteger)testTaskCount {
    @synchronized (self) { return _tasks.count; }
}
- (void)testExpireTasks {
    NSArray *handlers;
    @synchronized (self) { handlers = _tasks.allValues; }
    for (void (^handler)(void) in handlers) handler();
}
@end

@implementation NSOperationQueue (TestQoS)
- (void)setQualityOfService:(NSQualityOfService)quality {}
@end

@implementation UIColor
+ (instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    UIColor *c = [self new];
    c.r = r; c.g = g; c.b = b; c.a = a;
    return c;
}
+ (instancetype)blackColor { return [self colorWithRed:0 green:0 blue:0 alpha:1]; }
- (CGColorRef)CGColor { return NULL; }
- (BOOL)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a {
    if (r) *r = self.r;
    if (g) *g = self.g;
    if (b) *b = self.b;
    if (a) *a = self.a;
    return YES;
}
- (BOOL)getWhite:(CGFloat *)w alpha:(CGFloat *)a { return NO; }
@end

@implementation NSValue (TestGeometry)
+ (instancetype)valueWithCGPoint:(CGPoint)p { return [self valueWithPoint:p]; }
- (CGPoint)CGPointValue { return [self pointValue]; }
@end

@implementation UIBezierPath
+ (instancetype)bezierPath { return [self new]; }
- (void)moveToPoint:(CGPoint)p { [self doesNotRecognizeSelector:_cmd]; }
- (void)addLineToPoint:(CGPoint)p { [self doesNotRecognizeSelector:_cmd]; }
- (void)addQuadCurveToPoint:(CGPoint)p controlPoint:(CGPoint)c { [self doesNotRecognizeSelector:_cmd]; }
@end
