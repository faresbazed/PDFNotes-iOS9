// Run the reader's open method with controllable dispatch and a real annotation store.
#import "Models.h"
#include <assert.h>

static NSString *documents;
static BOOL openedPDF, loadedInk, published;
static void (^prepare)(void), (^publish)(void);
typedef int dispatch_queue_t, dispatch_once_t;
#define DISPATCH_QUEUE_SERIAL 0
static int dispatch_queue_create(const char *label, int attr) { return 1; }
static int dispatch_get_main_queue(void) { return 2; }
static void dispatch_once(int *once, void (^job)(void)) { if (!(*once)++) job(); }
static void dispatch_async(int queue, void (^job)(void)) {
    if (queue == 1) { assert(NSThread.isMainThread); prepare = job; }
    else { assert(queue == 2 && !NSThread.isMainThread); publish = job; }
}

@interface ProbeStore : AnnotationStore
@end
@implementation ProbeStore
+ (NSString *)documentsDirectory { return documents; }
- (instancetype)initWithPDFPath:(NSString *)path {
    self = [super initWithPDFPath:path];
    if (self) loadedInk = !NSThread.isMainThread;
    return self;
}
@end

@interface PDFDoc : NSObject
- (instancetype)initWithPath:(NSString *)path;
@end
@implementation PDFDoc
- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) openedPDF = !NSThread.isMainThread;
    return self;
}
@end

@interface PDFCancelToken : NSObject
@property (atomic, getter=isCancelled) BOOL cancelled;
@end
@implementation PDFCancelToken
@end

@interface TestView : NSObject
@property BOOL hidden;
@property (copy) NSString *text;
- (void)startAnimating;
@end
@implementation TestView
- (void)startAnimating {}
@end

@interface TestReader : NSObject {
@public
    NSString *_pdfPath;
    TestView *_loadingOverlay, *_loadingLabel, *_spinner;
    PDFCancelToken *_openToken;
    PDFDoc *_doc;
    AnnotationStore *_store;
}
- (void)startOpeningDocument;
- (void)documentDidOpen;
@end
@implementation TestReader
#define AnnotationStore ProbeStore
#include "reader-open.inc"
#undef AnnotationStore
- (void)documentDidOpen { assert(NSThread.isMainThread); published = YES; }
@end

static void RunPreparation(void) {
    NSOperationQueue *queue = [NSOperationQueue new];
    assert(prepare);
    [queue addOperationWithBlock:prepare];
    [queue waitUntilAllOperationsAreFinished];
    prepare = nil;
}

int main(void) { @autoreleasepool {
    documents = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    TestReader *reader = [TestReader new];
    reader->_pdfPath = [documents stringByAppendingPathComponent:@"Reopen.pdf"];
    ProbeStore *seed = [[ProbeStore alloc] initWithPDFPath:reader->_pdfPath];
    Stroke *ink = [Stroke new];
    [ink addNormalizedPoint:CGPointMake(0.5, 0.5)];
    [seed addStroke:ink onPage:0];
    assert([seed flushSynchronously]);

    [reader startOpeningDocument];
    assert(!reader->_store && !openedPDF && !loadedInk && !published);
    reader->_openToken.cancelled = YES;
    RunPreparation();
    assert(!openedPDF && !publish);
    [reader startOpeningDocument];
    RunPreparation();
    assert(openedPDF && loadedInk && publish && !published);
    reader->_openToken.cancelled = YES;
    publish(); publish = nil;
    assert(!reader->_store && !published);
    [reader startOpeningDocument];
    RunPreparation();
    publish(); publish = nil;
    assert(published && reader->_doc && !reader->_openToken && [reader->_store strokesForPage:0].count == 1);
    puts("PASS: cold open returns before PDF/ink reads; Back suppresses queued and unpublished opens; reopened ink is installed on main");
    [[NSFileManager defaultManager] removeItemAtPath:documents error:NULL];
    return 0;
}}
