#import "LibraryFavorites.h"
#import "LibraryListing.h"

static int failures;
static void Check(BOOL ok, const char *message) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", message);
    if (!ok) failures++;
}

int main(void) { @autoreleasepool {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"library.favoritePDFPaths"];
    NSString *docs = @"/Documents";
    NSString *root = @"/Documents/Notes.pdf";
    NSString *folder = @"/Documents/Math";
    NSString *nested = @"/Documents/Math/Week 1/Notes.pdf";
    NSString *sibling = @"/Documents/Maths/Notes.pdf";
    NSString *notebook = @"/Documents/Math/Graph%2FGrid.PDF";
    NSString *moved = @"/Documents/Math/Week 1/Review.pdf";
    Check(PDFLibraryFavoritePaths(docs, defaults).count == 0, "no initial favorites");
    for (NSString *path in @[root, nested, sibling, notebook, root]) PDFSetLibraryFavorite(path, YES, docs, defaults);
    NSSet *expected = [NSSet setWithArray:@[root, nested, sibling, notebook]];
    Check([PDFLibraryFavoritePaths(docs, defaults) isEqualToSet:expected], "same names in different folders and percent signs stay distinct");
    NSSet *relocated = PDFLibraryFavoritePaths(@"/new/sandbox/Documents", defaults);
    Check(relocated.count == 4 && [relocated containsObject:@"/new/sandbox/Documents/Math/Graph%2FGrid.PDF"], "stored paths survive sandbox relocation");

    PDFRelocateLibraryFavorites(root, moved, NO, docs, defaults);
    NSSet *paths = PDFLibraryFavoritePaths(docs, defaults);
    Check(paths.count == 4 && ![paths containsObject:root] && [paths containsObject:moved], "document move preserves star only at destination");
    Check(![paths containsObject:@"/Documents/Math/Week 1/Review-Copy.pdf"], "copy has an independent favorite state");
    PDFRelocateLibraryFavorites(folder, @"/Documents/Physics", YES, docs, defaults);
    expected = [NSSet setWithArray:@[@"/Documents/Physics/Week 1/Review.pdf", @"/Documents/Physics/Week 1/Notes.pdf", @"/Documents/Physics/Graph%2FGrid.PDF", sibling]];
    Check([PDFLibraryFavoritePaths(docs, defaults) isEqualToSet:expected], "folder rename moves descendants but not prefix siblings");
    PDFRelocateLibraryFavorites(@"/Documents/Physics/Graph%2FGrid.PDF", nil, NO, docs, defaults);
    Check(PDFLibraryFavoritePaths(docs, defaults).count == 3 && ![PDFLibraryFavoritePaths(docs, defaults) containsObject:@"/Documents/Physics/Graph%2FGrid.PDF"], "deleted PDF does not leave its star for a replacement");
    PDFRelocateLibraryFavorites(@"/Documents/Physics", nil, YES, docs, defaults);
    Check([PDFLibraryFavoritePaths(docs, defaults) isEqualToSet:[NSSet setWithObject:sibling]], "folder deletion clears only descendants");
    PDFSetLibraryFavorite(sibling, NO, docs, defaults);
    for (NSString *path in @[@"/DocumentsElsewhere/A.pdf", @"/Documents/../A.pdf", @"/Documents/.Hidden/A.pdf", @"/Documents/Inbox/A.pdf", @"/Documents/Annotations/A.pdf", @"/Documents/Notes.txt"]) {
        PDFSetLibraryFavorite(path, YES, docs, defaults);
    }
    Check(PDFLibraryFavoritePaths(docs, defaults).count == 0, "unfavorite removes star; invalid paths are not added");
    PDFSetLibraryFavorite(root, YES, docs, defaults);
    PDFRelocateLibraryFavorites(root, @"/Documents/.Private.pdf", NO, docs, defaults);
    Check(!PDFLibraryFavoritePaths(docs, defaults).count, "renaming a favorite to a hidden filename clears its old star");

    NSFileManager *fm = [NSFileManager defaultManager];
    docs = [[NSTemporaryDirectory() stringByResolvingSymlinksInPath] stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    folder = [docs stringByAppendingPathComponent:@"Courses"];
    [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    root = [docs stringByAppendingPathComponent:@"Root.pdf"];
    nested = [folder stringByAppendingPathComponent:@"Graph Notebook.pdf"];
    NSString *gone = [docs stringByAppendingPathComponent:@"Removed.pdf"];
    NSString *replaced = [docs stringByAppendingPathComponent:@"Now A Folder.pdf"];
    [fm createDirectoryAtPath:replaced withIntermediateDirectories:NO attributes:nil error:NULL];
    for (NSString *path in @[root, nested, [folder stringByAppendingPathComponent:@"Unstarred.pdf"]]) {
        [fm createFileAtPath:path contents:[NSData data] attributes:nil];
    }
    for (NSString *path in @[root, nested, gone, replaced]) PDFSetLibraryFavorite(path, YES, docs, defaults);
    paths = PDFLibraryFavoritePaths(docs, defaults);
    NSSet *available = [NSSet setWithArray:[PDFScanLibrary(docs, docs, NO, paths, nil) valueForKey:@"fullPath"]];
    Check([available isEqualToSet:[NSSet setWithArray:@[root, nested]]], "Favorites view includes nested and root favorites, not ordinary PDFs, missing files or directories");
    [fm removeItemAtPath:docs error:NULL];
    [defaults removeObjectForKey:@"library.favoritePDFPaths"];
    return failures ? 1 : 0;
}}
