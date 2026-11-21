#import <Foundation/Foundation.h>

NSString *PDFAnnotationKey(NSString *path, NSString *documents);
NSString *PDFLegacyAnnotationFile(NSString *path, NSString *documents);
void PDFDeleteAnnotations(NSString *path, BOOL directory, NSString *documents, NSUserDefaults *defaults);
void PDFMoveAnnotations(NSString *oldPath, NSString *newPath, BOOL directory, NSString *documents, NSUserDefaults *defaults);
void PDFMigrateAnnotations(NSString *documents, NSUserDefaults *defaults);
