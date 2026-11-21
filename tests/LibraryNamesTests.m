static int failures;
static void Check(BOOL ok, const char *message) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", message);
    if (!ok) failures++;
}
static BOOL Exists(NSString *relative) {
    return [[NSFileManager defaultManager] fileExistsAtPath:[docs stringByAppendingPathComponent:relative]];
}
static void Touch(NSString *relative) {
    NSString *path = [docs stringByAppendingPathComponent:relative];
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"fixture" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}
static void Reset(void) {
    if (docs) [[NSFileManager defaultManager] removeItemAtPath:docs error:NULL];
    docs = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    Touch(@"Course/Lecture1.pdf");
    Touch(@"Course/Week2/Slides.pdf");
    Touch(@"Annotations/Course%2FLecture1.pdf.plist");
    Touch(@"Annotations/Course%2FWeek2%2FSlides.pdf.plist");
}
int main(void) { @autoreleasepool {
    for (NSString *name in @[@"Inbox", @"Annotations", @"inbox", @"ANNOTATIONS"]) {
        Reset();
        [[NSFileManager defaultManager] removeItemAtPath:[docs stringByAppendingPathComponent:@"Annotations"] error:NULL];
        Check(!Rename([docs stringByAppendingPathComponent:@"Course"], YES, name),
              [[NSString stringWithFormat:@"reject root folder rename to %@ without existing destination", name] UTF8String]);
    }
    Reset();
    BOOL renamed = Rename([docs stringByAppendingPathComponent:@"Course"], YES, @"Inbox");
    Sweep();
    printf("REPRO: rename accepted=%d; subfolder PDF survives=%d; orphaned Inbox plist=%d\n", renamed,
           Exists(@"Course/Week2/Slides.pdf"), Exists(@"Annotations/Inbox%2FLecture1.pdf.plist"));
    Check(Exists(@"Course/Week2/Slides.pdf"), "subfolder PDF survives sweep");
    Check(Exists(@"Annotations/Course%2FLecture1.pdf.plist") && !Exists(@"Annotations/Inbox%2FLecture1.pdf.plist"), "annotations remain attached, no orphaned plist");
    Reset();
    Check(!Rename([docs stringByAppendingPathComponent:@"Course"], YES, @"  "), "empty name rejected");
    Check(!Rename([docs stringByAppendingPathComponent:@"Course"], YES, @"Course"), "unchanged name is a no-op");
    Touch(@"Taken/Other.pdf");
    Check(!Rename([docs stringByAppendingPathComponent:@"Course"], YES, @"Taken"), "existing destination rejected");
    Check(Rename([docs stringByAppendingPathComponent:@"Course"], YES, @"Reading"), "ordinary root folder rename accepted");
    Check(Exists(@"Reading/Week2/Slides.pdf") && Exists(@"Annotations/Reading%2FWeek2%2FSlides.pdf.plist"), "ordinary rename carries nested annotations");
    Check(Rename([docs stringByAppendingPathComponent:@"Reading/Week2"], YES, @"Inbox"), "nested reserved folder name accepted");
    Check(Rename([docs stringByAppendingPathComponent:@"Reading/Lecture1.pdf"], NO, @"Inbox"), "PDF basename Inbox accepted");
    Check(!Rename([docs stringByAppendingPathComponent:@"Missing"], YES, @"Other"), "missing source fails safely");
    [[NSFileManager defaultManager] removeItemAtPath:docs error:NULL];
    printf("Library names: %d failures\n", failures);
    return failures ? 1 : 0;
}}
