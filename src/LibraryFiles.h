#import <Foundation/Foundation.h>

NSString *PDFUniqueDestination(NSString *directory, NSString *filename);
NSString *PDFImportDocument(NSString *sourcePath, NSString *documents, NSError **error);
void PDFImportInboxDocuments(NSString *documents);
