#import "AnnotationFiles.h"

static NSString *EscapeKey(NSString *relativePath) {
    return [[relativePath stringByReplacingOccurrencesOfString:@"%" withString:@"%25"]
            stringByReplacingOccurrencesOfString:@"/" withString:@"%2F"];
}

static NSString *RelativePath(NSString *path, NSString *documents) {
    NSString *resolved = [path stringByResolvingSymlinksInPath] ?: [path stringByStandardizingPath];
    NSString *prefix = [documents hasSuffix:@"/"] ? documents : [documents stringByAppendingString:@"/"];
    if (![resolved hasPrefix:prefix]) return nil;
    NSString *rel = [resolved substringFromIndex:prefix.length];
    return rel.length > 0 ? rel : nil;
}

NSString *PDFAnnotationKey(NSString *pdfPath, NSString *documents) {
    if (pdfPath.length == 0) return @"untitled.pdf";
    NSString *rel = RelativePath(pdfPath, documents);
    if (rel) return EscapeKey(rel);
    NSString *resolved = [pdfPath stringByResolvingSymlinksInPath] ?: [pdfPath stringByStandardizingPath];
    return EscapeKey([resolved lastPathComponent]);
}

static NSArray<NSString *> *LibraryPDFs(NSString *documents) {
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:documents];
    if (!enumerator) return nil;
    NSMutableArray<NSString *> *pdfs = [NSMutableArray array];
    NSString *relative;
    while ((relative = [enumerator nextObject])) {
        NSString *first = [[relative pathComponents] firstObject];
        if ([first isEqualToString:@"Annotations"] || [first isEqualToString:@"Inbox"] ||
            [[relative lastPathComponent] hasPrefix:@"."]) {
            [enumerator skipDescendents];
            continue;
        }
        NSDictionary *attributes = [enumerator fileAttributes];
        if ([[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeRegular] &&
            [[relative.pathExtension lowercaseString] isEqualToString:@"pdf"]) [pdfs addObject:relative];
    }
    return pdfs;
}

static NSString *AnnotationFile(NSString *path, NSString *documents) {
    return [[documents stringByAppendingPathComponent:@"Annotations"] stringByAppendingPathComponent:[PDFAnnotationKey(path, documents) stringByAppendingPathExtension:@"plist"]];
}

// v1/v2.0 keyed annotations by file name alone. That file belongs to a document only when it is
// the sole library PDF with that name; otherwise it is another document's (or an ambiguous) file.
NSString *PDFLegacyAnnotationFile(NSString *pdfPath, NSString *documents) {
    NSString *relative = pdfPath.length > 0 ? RelativePath(pdfPath, documents) : nil;
    if (!relative) return nil;
    NSString *name = [relative lastPathComponent];
    NSString *legacy = [[documents stringByAppendingPathComponent:@"Annotations"] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
    if ([legacy isEqualToString:AnnotationFile(pdfPath, documents)] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:legacy]) return nil;
    BOOL listed = NO;
    for (NSString *other in LibraryPDFs(documents)) {
        if (![[other lastPathComponent] isEqualToString:name]) continue;
        if (![other isEqualToString:relative]) return nil;
        listed = YES;
    }
    return listed ? legacy : nil;
}

void PDFDeleteAnnotations(NSString *itemPath, BOOL isDirectory, NSString *documents, NSUserDefaults *defaults) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!isDirectory) {
        NSString *plistPath = AnnotationFile(itemPath, documents);
        [fm removeItemAtPath:plistPath error:NULL];
        NSString *key = PDFAnnotationKey(itemPath, documents);
        [defaults removeObjectForKey:[NSString stringWithFormat:@"lastPage.%@", key]];
        return;
    }

    NSString *docs = documents;
    NSString *resolved = [itemPath stringByResolvingSymlinksInPath] ?: [itemPath stringByStandardizingPath];
    NSString *docsPrefix = [docs hasSuffix:@"/"] ? docs : [docs stringByAppendingString:@"/"];
    if (![resolved hasPrefix:docsPrefix]) return;

    NSString *relDir = [resolved substringFromIndex:docsPrefix.length];
    NSString *keyPrefix = [EscapeKey(relDir) stringByAppendingString:@"%2F"];
    NSString *annDir = [documents stringByAppendingPathComponent:@"Annotations"];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:annDir error:NULL];
    for (NSString *f in files) {
        if ([f hasPrefix:keyPrefix]) {
            [fm removeItemAtPath:[annDir stringByAppendingPathComponent:f] error:NULL];
        }
    }
    NSString *defaultsPrefix = [@"lastPage." stringByAppendingString:keyPrefix];
    for (NSString *key in [defaults dictionaryRepresentation]) {
        if ([key hasPrefix:defaultsPrefix]) [defaults removeObjectForKey:key];
    }
}

void PDFMoveAnnotations(NSString *oldPath, NSString *newPath, BOOL isDirectory, NSString *documents, NSUserDefaults *defaults) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!isDirectory) {
        NSString *oldPlist = AnnotationFile(oldPath, documents);
        NSString *newPlist = AnnotationFile(newPath, documents);
        if (![oldPlist isEqualToString:newPlist] && [fm fileExistsAtPath:oldPlist]) {
            [fm removeItemAtPath:newPlist error:NULL];
            [fm moveItemAtPath:oldPlist toPath:newPlist error:NULL];
        }
        NSString *oldDef = [NSString stringWithFormat:@"lastPage.%@", PDFAnnotationKey(oldPath, documents)];
        NSString *newDef = [NSString stringWithFormat:@"lastPage.%@", PDFAnnotationKey(newPath, documents)];
        id last = [defaults objectForKey:oldDef];
        if (last && ![oldDef isEqualToString:newDef]) {
            [defaults setObject:last forKey:newDef];
            [defaults removeObjectForKey:oldDef];
        }
        return;
    }

    NSString *docs = documents;
    NSString *docsPrefix = [docs hasSuffix:@"/"] ? docs : [docs stringByAppendingString:@"/"];
    NSString *oldRes = [oldPath stringByResolvingSymlinksInPath] ?: [oldPath stringByStandardizingPath];
    NSString *newRes = [newPath stringByResolvingSymlinksInPath] ?: [newPath stringByStandardizingPath];
    if (![oldRes hasPrefix:docsPrefix] || ![newRes hasPrefix:docsPrefix]) return;

    NSString *oldRel = [oldRes substringFromIndex:docsPrefix.length];
    NSString *newRel = [newRes substringFromIndex:docsPrefix.length];
    NSString *oldKeyPrefix = [EscapeKey(oldRel) stringByAppendingString:@"%2F"];
    NSString *newKeyPrefix = [EscapeKey(newRel) stringByAppendingString:@"%2F"];
    if ([oldKeyPrefix isEqualToString:newKeyPrefix]) return;

    NSString *annDir = [documents stringByAppendingPathComponent:@"Annotations"];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:annDir error:NULL];
    for (NSString *f in files) {
        if ([f hasPrefix:oldKeyPrefix]) {
            NSString *suffix = [f substringFromIndex:oldKeyPrefix.length];
            NSString *destName = [newKeyPrefix stringByAppendingString:suffix];
            NSString *src = [annDir stringByAppendingPathComponent:f];
            NSString *dst = [annDir stringByAppendingPathComponent:destName];
            [fm removeItemAtPath:dst error:NULL];
            [fm moveItemAtPath:src toPath:dst error:NULL];
        }
    }
    NSString *oldDefaultsPrefix = [@"lastPage." stringByAppendingString:oldKeyPrefix];
    NSString *newDefaultsPrefix = [@"lastPage." stringByAppendingString:newKeyPrefix];
    NSDictionary *values = [defaults dictionaryRepresentation];
    for (NSString *key in values) {
        if ([key hasPrefix:oldDefaultsPrefix]) {
            NSString *dest = [newDefaultsPrefix stringByAppendingString:[key substringFromIndex:oldDefaultsPrefix.length]];
            [defaults setObject:[values objectForKey:key] forKey:dest];
            [defaults removeObjectForKey:key];
        }
    }
}

void PDFMigrateAnnotations(NSString *documents, NSUserDefaults *defaults) {
    NSString *flag = @"annotationKeysPercentEscapedV1";
    if ([defaults boolForKey:flag]) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *annDir = [documents stringByAppendingPathComponent:@"Annotations"];
    NSMutableDictionary *claimants = [NSMutableDictionary dictionary];
    NSMutableSet *currentKeys = [NSMutableSet set];
    NSArray<NSString *> *pdfs = LibraryPDFs(documents);
    if (!pdfs) return;
    for (NSString *relative in pdfs) {
        NSString *legacy = [relative stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
        NSString *key = EscapeKey(relative);
        [currentKeys addObject:key];
        if (![legacy isEqualToString:key]) {
            NSMutableArray *keys = [claimants objectForKey:legacy];
            if (!keys) {
                keys = [NSMutableArray array];
                [claimants setObject:keys forKey:legacy];
            }
            [keys addObject:key];
        }
    }
    NSMutableDictionary *legacyData = [NSMutableDictionary dictionary];
    NSDictionary *oldDefaults = [defaults dictionaryRepresentation];
    BOOL success = YES;
    for (NSString *legacy in claimants) {
        NSString *path = [annDir stringByAppendingPathComponent:[legacy stringByAppendingPathExtension:@"plist"]];
        if ([fm fileExistsAtPath:path]) {
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (data) [legacyData setObject:data forKey:legacy];
            else success = NO;
        }
    }
    NSMutableSet *migratedFiles = [NSMutableSet set];
    NSMutableSet *migratedDefaults = [NSMutableSet set];
    NSMutableSet *completed = [NSMutableSet set];
    NSMutableSet *pending = [NSMutableSet setWithArray:[claimants allKeys]];
    BOOL progress = YES;
    while (pending.count > 0 && progress) {
        progress = NO;
        for (NSString *legacy in [pending allObjects]) {
            BOOL ready = YES;
            for (NSString *key in [claimants objectForKey:legacy]) {
                if ([claimants objectForKey:key] && ![completed containsObject:key]) ready = NO;
            }
            if (!ready) continue;
            NSData *data = [legacyData objectForKey:legacy];
            NSString *oldDefault = [@"lastPage." stringByAppendingString:legacy];
            id page = [oldDefaults objectForKey:oldDefault];
            BOOL copied = YES;
            NSString *source = [annDir stringByAppendingPathComponent:[legacy stringByAppendingPathExtension:@"plist"]];
            if (!data && [fm fileExistsAtPath:source]) copied = NO;
            for (NSString *key in [claimants objectForKey:legacy]) {
                BOOL destinationIsLegacy = [claimants objectForKey:key] != nil;
                NSString *dest = [annDir stringByAppendingPathComponent:[key stringByAppendingPathExtension:@"plist"]];
                BOOL directory = NO;
                BOOL exists = [fm fileExistsAtPath:dest isDirectory:&directory];
                if (data && (directory || ((destinationIsLegacy || !exists) && ![data writeToFile:dest atomically:YES]))) {
                    copied = NO;
                }
            }
            if (copied) {
                for (NSString *key in [claimants objectForKey:legacy]) {
                    NSString *newDefault = [@"lastPage." stringByAppendingString:key];
                    if (page && ([claimants objectForKey:key] || ![defaults objectForKey:newDefault])) [defaults setObject:page forKey:newDefault];
                }
                if (data) [migratedFiles addObject:legacy];
                if (page) [migratedDefaults addObject:legacy];
                [completed addObject:legacy];
            } else {
                success = NO;
            }
            [pending removeObject:legacy];
            progress = YES;
        }
    }
    if (pending.count > 0) success = NO;
    for (NSString *legacy in migratedFiles) {
        if (![currentKeys containsObject:legacy]) {
            NSString *path = [annDir stringByAppendingPathComponent:[legacy stringByAppendingPathExtension:@"plist"]];
            if (![fm removeItemAtPath:path error:NULL]) success = NO;
        }
    }
    for (NSString *legacy in migratedDefaults) {
        if (![currentKeys containsObject:legacy]) [defaults removeObjectForKey:[@"lastPage." stringByAppendingString:legacy]];
    }
    if (success) [defaults setBool:YES forKey:flag];
}
