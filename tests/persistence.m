#import "Models.h"

static NSString *documents;
static NSCondition *gate;
static BOOL entered, releaseWriter, encodedOnMain;
static int failures;

@interface TempStore : AnnotationStore
@property NSUInteger snapshots;
@end
@interface AnnotationStore (TestAutosave)
- (NSOperation *)newWrite;
- (void)autosave;
@end
@implementation TempStore
+ (NSString *)documentsDirectory { return documents; }
- (NSOperation *)newWrite {
    self.snapshots++;
    return [super newWrite];
}
@end

@interface PausingStroke : Stroke
@end
@implementation PausingStroke
- (NSDictionary *)toDictionary {
    [gate lock];
    entered = YES;
    encodedOnMain |= NSThread.isMainThread;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
    while (!releaseWriter && !NSThread.isMainThread && [gate waitUntilDate:deadline]) {}
    [gate unlock];
    return [super toDictionary];
}
@end

static void Check(BOOL ok, const char *name) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok) failures++;
}

static Stroke *MakeStroke(Class type, int points) {
    Stroke *s = [[type alloc] init];
    for (int i = 0; i < points; i++) [s addNormalizedPoint:CGPointMake(i % 80 / 80., i % 100 / 100.)];
    return s;
}

static void TestConcurrentEdits(void) {
    NSString *pdf = [documents stringByAppendingPathComponent:@"Ink.pdf"];
    TempStore *store = [[TempStore alloc] initWithPDFPath:pdf];
    NSString *path = [TempStore annotationFilePathForPDFPath:pdf];
    [store addStroke:MakeStroke(PausingStroke.class, 4) onPage:1];
    TextNote *note = [TextNote new];
    note.normalizedPosition = CGPointMake(0.25, 0.5);
    [store saveNote:note onPage:1];
    [store toggleBookmarkForPage:1];
    store.lastPageIndex = 1;

    // Let the real debounce run, but hold the worker inside stroke serialization.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    BOOL started = NO;
    while (!started && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        [gate lock]; started = entered; [gate unlock];
    }
    Check(started && !encodedOnMain, "debounce runs point serialization off the calling thread");
    [store moveNoteWithID:note.identifier toNormalizedPosition:CGPointMake(0.75, 0.5) onPage:1 recordUndo:YES];
    [store toggleBookmarkForPage:1];
    [store addStroke:MakeStroke(Stroke.class, 3) onPage:1];
    store.lastPageIndex = 2;
    [store autosave];
    Check(store.snapshots == 1, "edits during a slow write do not queue additional snapshots");

    [gate lock]; releaseWriter = YES; [gate broadcast]; [gate unlock];
    // No main run loop here: inspect the first completed snapshot before the next debounce.
    deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (![[NSFileManager defaultManager] fileExistsAtPath:path] && deadline.timeIntervalSinceNow > 0)
        [NSThread sleepForTimeInterval:0.005];
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:path];
    Check([saved[@"pages"][@"1"] count] == 1 && [saved[@"notes"][@"1"][0][@"x"] doubleValue] == 0.25 &&
          [saved[@"bookmarks"] isEqual:@[@1]] && [saved[@"lastPage"] integerValue] == 1,
          "in-flight snapshot retains its own strokes, note position, bookmarks and page");

    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    TempStore *reopened = [[TempStore alloc] initWithPDFPath:pdf];
    Check([reopened strokesForPage:1].count == 2 && [reopened notesForPage:1][0].normalizedPosition.x == 0.75 &&
          ![reopened isPageBookmarked:1] && reopened.lastPageIndex == 2, "background flush persists newer edits before returning");
    [store clearPage:1];
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    Check(![[NSFileManager defaultManager] fileExistsAtPath:path], "clear plus lifecycle flush removes the old sidecar");
}

static void TestRetry(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *pdf = [documents stringByAppendingPathComponent:@"Retry.pdf"];
    TempStore *store = [[TempStore alloc] initWithPDFPath:pdf];
    NSString *path = [TempStore annotationFilePathForPDFPath:pdf];
    // A directory in place of the file reliably rejects the atomic write, even as root.
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:NULL]) abort();
    [store addStroke:MakeStroke(Stroke.class, 3) onPage:0];
    [store autosave];
    Check(![store flushSynchronously], "failed autosave and close flush are not treated as saved");
    [fm removeItemAtPath:path error:NULL];
    Check([store flushSynchronously] && [[[[TempStore alloc] initWithPDFPath:pdf] strokesForPage:0] count] == 1,
          "retry persists previously failed edits without requiring another edit");
}

static void Benchmark(void) {
    NSString *pdf = [documents stringByAppendingPathComponent:@"Bench.pdf"];
    TempStore *store = [[TempStore alloc] initWithPDFPath:pdf];
    for (int i = 0; i < 300; i++) {
        @autoreleasepool { [store addStroke:MakeStroke(Stroke.class, 100) onPage:i / 30]; }
    }
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    [store autosave];
    printf("Main-thread autosave callback (300 strokes, 30,000 points): %.2f ms\n",
           ([NSDate timeIntervalSinceReferenceDate] - start) * 1000);
    BOOL ok = [store flushSynchronously];
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:[TempStore annotationFilePathForPDFPath:pdf]];
    Check(ok && [root[@"pages"] count] == 10 && [root[@"pages"][@"9"][29][@"pts"] count] == 100,
          "explicit flush drains the outstanding write before returning");
}

static void TestOverlongSidecar(void) {
    NSString *part = [@"p" stringByPaddingToLength:130 withString:@"p" startingAtIndex:0];
    NSString *dir = [documents stringByAppendingPathComponent:part];
    NSString *pdf = [dir stringByAppendingPathComponent:[part stringByAppendingPathExtension:@"pdf"]];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL] ||
        ![fm createFileAtPath:pdf contents:nil attributes:nil]) abort();
    TempStore *store = [[TempStore alloc] initWithPDFPath:pdf];
    [store addStroke:MakeStroke(Stroke.class, 2) onPage:0];
    Check(![store flushSynchronously], "overlong sidecar cannot silently report a saved edit");
    [store undoReturningPage];
    Check([store flushSynchronously], "undoing every edit needs no overlong sidecar to be removed");

    NSDictionary *legacy = @{@"lastPage": @5, @"pages": @{@"0": @[[MakeStroke(Stroke.class, 2) toDictionary]]}};
    NSString *legacyPath = [[documents stringByAppendingPathComponent:@"Annotations"]
                            stringByAppendingPathComponent:[pdf.lastPathComponent stringByAppendingPathExtension:@"plist"]];
    if (![legacy writeToFile:legacyPath atomically:YES]) abort();
    TempStore *legacyStore = [[TempStore alloc] initWithPDFPath:pdf];
    Check([legacyStore strokesForPage:0].count == 1, "overlong primary loads the original legacy file");
    [legacyStore clearPage:0];
    Check(![legacyStore flushSynchronously], "cannot report clearing legacy ink if the empty primary cannot be written");

    NSString *shortPDF = [dir stringByAppendingPathComponent:@"Short.pdf"];
    NSString *shortLegacy = [[legacyPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Short.pdf.plist"];
    if (![fm createFileAtPath:shortPDF contents:nil attributes:nil] || ![legacy writeToFile:shortLegacy atomically:YES]) abort();
    TempStore *shortStore = [[TempStore alloc] initWithPDFPath:shortPDF];
    Check([shortStore strokesForPage:0].count == 1, "short primary also falls back to legacy ink");
    [shortStore clearPage:0];
    Check([shortStore flushSynchronously] && [[[[TempStore alloc] initWithPDFPath:shortPDF] strokesForPage:0] count] == 0 &&
          [fm fileExistsAtPath:shortLegacy], "clearing survives reopen without deleting a legacy file");
    Check([[TempStore alloc] initWithPDFPath:shortPDF].lastPageIndex == 5,
          "clearing without scrolling preserves the page inherited from a legacy file");
    shortStore.lastPageIndex = 9;
    Check([[TempStore alloc] initWithPDFPath:shortPDF].lastPageIndex == 9,
          "empty legacy override does not mask later reading progress");
}

int main(void) { @autoreleasepool {
    documents = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    gate = [NSCondition new];
    TestConcurrentEdits();
    TestRetry();
    TestOverlongSidecar();
    Benchmark();
    [[NSFileManager defaultManager] removeItemAtPath:documents error:NULL];
    return failures ? 1 : 0;
}}
