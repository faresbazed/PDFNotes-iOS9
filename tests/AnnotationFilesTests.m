#import "AnnotationFiles.h"
#include <stdio.h>

static int failures;
static void Check(BOOL ok, const char *name) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok) failures++;
}
static NSString *File(NSString *docs, NSString *key) {
    return [[docs stringByAppendingPathComponent:@"Annotations"] stringByAppendingPathComponent:[key stringByAppendingPathExtension:@"plist"]];
}
static void Write(NSString *path) {
    [@"fixture" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}
int main(void) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *docs = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [fm createDirectoryAtPath:[docs stringByAppendingPathComponent:@"Annotations"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [fm createDirectoryAtPath:[docs stringByAppendingPathComponent:@"Course"] withIntermediateDirectories:YES attributes:nil error:NULL];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults removeObjectForKey:@"annotationKeysPercentEscapedV1"];
        NSString *nested = [docs stringByAppendingPathComponent:@"Course/Lecture.pdf"];
        NSString *root = [docs stringByAppendingPathComponent:@"Course__Lecture.pdf"];
        NSString *folder = [docs stringByAppendingPathComponent:@"Course"];
        NSString *renamed = [docs stringByAppendingPathComponent:@"Renamed"];
        NSString *nk = PDFAnnotationKey(nested, docs);
        NSString *rk = PDFAnnotationKey(root, docs);
        Check(![nk isEqual:rk], "distinct keys");
        Check([PDFAnnotationKey([docs stringByAppendingPathComponent:@"A%2FB/C.pdf"], docs) isEqual:@"A%252FB%2FC.pdf"], "percent escaped before slash");
        Write(File(docs, rk)); Write(File(docs, nk));
        [defaults setInteger:0 forKey:@"lastPage.Course%2FLecture.pdf"];
        [defaults setInteger:3 forKey:@"lastPage.Course__Lecture.pdf"];
        PDFDeleteAnnotations(folder, YES, docs, defaults);
        Check([fm fileExistsAtPath:File(docs, rk)] && ![fm fileExistsAtPath:File(docs, @"Course%2FLecture.pdf")], "folder delete preserves root");
        Check(![defaults objectForKey:@"lastPage.Course%2FLecture.pdf"] && [defaults integerForKey:@"lastPage.Course__Lecture.pdf"] == 3, "folder delete defaults isolated");
        Write(File(docs, rk)); Write(File(docs, nk));
        [defaults setInteger:0 forKey:@"lastPage.Course%2FLecture.pdf"];
        PDFMoveAnnotations(folder, renamed, YES, docs, defaults);
        Check([fm fileExistsAtPath:File(docs, rk)] && [fm fileExistsAtPath:File(docs, @"Renamed%2FLecture.pdf")], "folder rename preserves root");
        Check([defaults objectForKey:@"lastPage.Renamed%2FLecture.pdf"] && ![defaults objectForKey:@"lastPage.Course%2FLecture.pdf"] && [defaults integerForKey:@"lastPage.Course__Lecture.pdf"] == 3, "folder rename defaults isolated");
        Write(nested); Write(root);
        Write([docs stringByAppendingPathComponent:@"Course/Only.pdf"]);
        Write(File(docs, @"Course__Only.pdf"));
        Write([docs stringByAppendingPathComponent:@"Course/Existing.pdf"]);
        Write(File(docs, @"Course__Existing.pdf"));
        [@"new" writeToFile:File(docs, @"Course%2FExisting.pdf") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [defaults setInteger:5 forKey:@"lastPage.Course__Only.pdf"];
        Write([docs stringByAppendingPathComponent:@"Root.pdf"]); Write(File(docs, @"Root.pdf"));
        [defaults setInteger:7 forKey:@"lastPage.Course__Lecture.pdf"];
        PDFMigrateAnnotations(docs, defaults);
        Check([fm fileExistsAtPath:File(docs, @"Course%2FLecture.pdf")] && [fm fileExistsAtPath:File(docs, rk)], "migration copies shared legacy to both claimants");
        Check([PDFAnnotationKey([docs stringByAppendingPathComponent:@"Root.pdf"], docs) isEqual:@"Root.pdf"] && [fm fileExistsAtPath:File(docs, @"Root.pdf")], "root-only key unchanged");
        Check([defaults integerForKey:@"lastPage.Course%2FLecture.pdf"] == 7 && [defaults integerForKey:@"lastPage.Course__Lecture.pdf"] == 7, "lastPage migration preserves shared root");
        Check([fm fileExistsAtPath:File(docs, @"Course%2FOnly.pdf")] && ![fm fileExistsAtPath:File(docs, @"Course__Only.pdf")] && [defaults integerForKey:@"lastPage.Course%2FOnly.pdf"] == 5 && ![defaults objectForKey:@"lastPage.Course__Only.pdf"], "unclaimed legacy keys removed");
        Check([[NSString stringWithContentsOfFile:File(docs, @"Course%2FExisting.pdf") encoding:NSUTF8StringEncoding error:NULL] isEqual:@"new"], "migration preserves existing destination");
        [fm removeItemAtPath:File(docs, @"Course%2FLecture.pdf") error:NULL];
        PDFMigrateAnnotations(docs, defaults);
        Check(![fm fileExistsAtPath:File(docs, @"Course%2FLecture.pdf")] && [defaults boolForKey:@"annotationKeysPercentEscapedV1"], "second migration is no-op");
        Check([PDFAnnotationKey(nil, docs) isEqual:@"untitled.pdf"], "empty path");
        PDFDeleteAnnotations(@"/outside", YES, docs, defaults);
        PDFMoveAnnotations(@"/outside", renamed, YES, docs, defaults);
        Check([fm fileExistsAtPath:File(docs, rk)], "outside paths ignored");
        [fm removeItemAtPath:docs error:NULL];
        for (NSString *key in @[@"annotationKeysPercentEscapedV1", @"lastPage.Course__Lecture.pdf", @"lastPage.Course%2FLecture.pdf", @"lastPage.Renamed%2FLecture.pdf", @"lastPage.Course%2FOnly.pdf"]) [defaults removeObjectForKey:key];
    }
    printf("%d failure(s)\n", failures);
    return failures ? 1 : 0;
}
