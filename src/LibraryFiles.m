#import "LibraryFiles.h"

NSString *PDFUniqueDestination(NSString *directory, NSString *filename) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = [filename stringByDeletingPathExtension];
    NSString *ext = [filename pathExtension];
    if (base.length == 0) base = @"Document";
    NSString *candidate = [directory stringByAppendingPathComponent:filename];
    NSInteger n = 2;
    while ([fm fileExistsAtPath:candidate]) {
        NSString *name = [NSString stringWithFormat:@"%@-%ld", base, (long)n++];
        if (ext.length) name = [name stringByAppendingPathExtension:ext];
        candidate = [directory stringByAppendingPathComponent:name];
    }
    return candidate;
}

NSString *PDFImportDocument(NSString *sourcePath, NSString *documents, NSError **error) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *source = [sourcePath stringByResolvingSymlinksInPath];
    NSDictionary *attributes = [fm attributesOfItemAtPath:source error:error];
    if (!attributes) return nil;
    if (![[attributes fileType] isEqualToString:NSFileTypeRegular]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError
                                            userInfo:@{NSLocalizedDescriptionKey: @"Choose a PDF file, not a folder."}];
        return nil;
    }

    documents = [documents stringByResolvingSymlinksInPath];
    NSString *inbox = [documents stringByAppendingPathComponent:@"Inbox"];
    BOOL inInbox = [source hasPrefix:[inbox stringByAppendingString:@"/"]];
    if (!inInbox && [source hasPrefix:[documents stringByAppendingString:@"/"]]) return source;

    NSString *name = [source lastPathComponent];
    if (!name.pathExtension.length) name = [name stringByAppendingPathExtension:@"pdf"];
    NSString *dest = PDFUniqueDestination(documents, name);
    if (inInbox) {
        // Inbox and the library share a volume. A failed move leaves the source for retry.
        return [fm moveItemAtPath:source toPath:dest error:error] ? dest : nil;
    }

    // Do not expose an incomplete external copy to the library.
    NSString *staging = [documents stringByAppendingPathComponent:[@"." stringByAppendingString:[[NSUUID UUID] UUIDString]]];
    BOOL imported = [fm copyItemAtPath:source toPath:staging error:error] &&
                    [fm moveItemAtPath:staging toPath:dest error:error];
    if (!imported) [fm removeItemAtPath:staging error:NULL];
    return imported ? dest : nil;
}

void PDFImportInboxDocuments(NSString *documents) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *inbox = [documents stringByAppendingPathComponent:@"Inbox"];
    for (NSString *name in [fm contentsOfDirectoryAtPath:inbox error:NULL]) {
        if ([name hasPrefix:@"."] || ![name.pathExtension.lowercaseString isEqualToString:@"pdf"]) continue;
        NSString *source = [inbox stringByAppendingPathComponent:name];
        if (![[[fm attributesOfItemAtPath:source error:NULL] fileType] isEqualToString:NSFileTypeRegular]) continue;
        PDFImportDocument(source, documents, NULL);
    }
}
