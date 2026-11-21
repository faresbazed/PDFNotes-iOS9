#import <Foundation/Foundation.h>

NSString *PDFSanitizeLibraryFilename(NSString *input);
BOOL PDFLibraryNameIsReserved(NSString *name);
BOOL PDFLibraryRenameNameIsReserved(NSString *name, BOOL rootLibrary, NSString *relativeFolder);
