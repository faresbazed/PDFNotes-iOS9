#import <Foundation/Foundation.h>

NSSet<NSString *> *PDFLibraryFavoritePaths(NSString *documents, NSUserDefaults *defaults);
NSDictionary *PDFFavoriteFileAttributes(NSString *path, NSString *documents);
void PDFSetLibraryFavorite(NSString *path, BOOL favorite, NSString *documents, NSUserDefaults *defaults);
// Pass nil as the destination after a successful deletion.
void PDFRelocateLibraryFavorites(NSString *from, NSString *to, BOOL directory, NSString *documents, NSUserDefaults *defaults);
