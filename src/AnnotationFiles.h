#import <Foundation/Foundation.h>

NSString *PDFAnnotationKey(NSString *path, NSString *documents);
BOOL PDFReadLibraryAnnotationSummary(NSString *pdfPath, NSString *documents, NSUserDefaults *defaults, NSInteger *lastPage);
NSString *PDFLegacyAnnotationFile(NSString *path, NSString *documents);
void PDFDeleteAnnotations(NSString *path, BOOL directory, NSString *documents, NSUserDefaults *defaults);
BOOL PDFDeleteLibraryItem(NSString *path, BOOL directory, NSString *documents, NSUserDefaults *defaults, NSError **error);
void PDFMoveAnnotations(NSString *oldPath, NSString *newPath, BOOL directory, NSString *documents, NSUserDefaults *defaults);
void PDFMigrateAnnotations(NSString *documents, NSUserDefaults *defaults);
