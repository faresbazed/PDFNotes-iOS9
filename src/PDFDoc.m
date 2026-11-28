#import "PDFDoc.h"
#import "PDFRasterSize.h"
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

@implementation PDFOutlineItem
@end

@implementation PDFSearchMatch
@end

@implementation PDFCancelToken
- (void)cancel {
    self.cancelled = YES;
}
@end

#pragma mark - PDF Text Scanner Context

typedef struct {
    __unsafe_unretained NSMutableString *buffer;
} PDFTextScanCtx;

static void PDFAppendPDFString(CGPDFStringRef pdfStr, NSMutableString *outStr) {
    if (!pdfStr || !outStr) return;
    CFStringRef cfStr = CGPDFStringCopyTextString(pdfStr);
    if (cfStr) {
        [outStr appendString:(__bridge NSString *)cfStr];
        CFRelease(cfStr);
        return;
    }
    const unsigned char *bytes = CGPDFStringGetBytePtr(pdfStr);
    size_t len = CGPDFStringGetLength(pdfStr);
    if (bytes && len > 0) {
        NSString *latin = [[NSString alloc] initWithBytes:bytes length:len encoding:NSISOLatin1StringEncoding];
        if (latin) [outStr appendString:latin];
    }
}

static void PDFOp_Tj(CGPDFScannerRef scanner, void *info) {
    PDFTextScanCtx *ctx = (PDFTextScanCtx *)info;
    CGPDFStringRef str = NULL;
    if (CGPDFScannerPopString(scanner, &str)) {
        PDFAppendPDFString(str, ctx->buffer);
    }
}

static void PDFOp_Quote(CGPDFScannerRef scanner, void *info) {
    PDFTextScanCtx *ctx = (PDFTextScanCtx *)info;
    [ctx->buffer appendString:@"\n"];
    CGPDFStringRef str = NULL;
    if (CGPDFScannerPopString(scanner, &str)) {
        PDFAppendPDFString(str, ctx->buffer);
    }
}

static void PDFOp_DoubleQuote(CGPDFScannerRef scanner, void *info) {
    PDFTextScanCtx *ctx = (PDFTextScanCtx *)info;
    [ctx->buffer appendString:@"\n"];
    CGPDFStringRef str = NULL;
    if (CGPDFScannerPopString(scanner, &str)) {
        PDFAppendPDFString(str, ctx->buffer);
    }
}

static void PDFOp_TJ(CGPDFScannerRef scanner, void *info) {
    PDFTextScanCtx *ctx = (PDFTextScanCtx *)info;
    CGPDFArrayRef arr = NULL;
    if (!CGPDFScannerPopArray(scanner, &arr) || !arr) return;
    size_t count = CGPDFArrayGetCount(arr);
    for (size_t i = 0; i < count; i++) {
        CGPDFObjectRef obj = NULL;
        if (!CGPDFArrayGetObject(arr, i, &obj) || !obj) continue;
        CGPDFObjectType type = CGPDFObjectGetType(obj);
        if (type == kCGPDFObjectTypeString) {
            CGPDFStringRef s = NULL;
            if (CGPDFObjectGetValue(obj, kCGPDFObjectTypeString, &s)) {
                PDFAppendPDFString(s, ctx->buffer);
            }
        } else if (type == kCGPDFObjectTypeReal || type == kCGPDFObjectTypeInteger) {
            CGPDFReal kern = 0.0;
            if (CGPDFObjectGetValue(obj, kCGPDFObjectTypeReal, &kern) && kern < -180.0) {
                [ctx->buffer appendString:@" "];
            }
        }
    }
}

static void PDFOp_Newline(CGPDFScannerRef scanner, void *info) {
    PDFTextScanCtx *ctx = (PDFTextScanCtx *)info;
    if (ctx->buffer.length > 0 && [ctx->buffer characterAtIndex:ctx->buffer.length - 1] != ' ') {
        [ctx->buffer appendString:@" "];
    }
}

static CGPDFOperatorTableRef PDFSharedOperatorTable(void) {
    static CGPDFOperatorTableRef table = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = CGPDFOperatorTableCreate();
        CGPDFOperatorTableSetCallback(table, "Tj", &PDFOp_Tj);
        CGPDFOperatorTableSetCallback(table, "TJ", &PDFOp_TJ);
        CGPDFOperatorTableSetCallback(table, "'", &PDFOp_Quote);
        CGPDFOperatorTableSetCallback(table, "\"", &PDFOp_DoubleQuote);
        CGPDFOperatorTableSetCallback(table, "Td", &PDFOp_Newline);
        CGPDFOperatorTableSetCallback(table, "TD", &PDFOp_Newline);
        CGPDFOperatorTableSetCallback(table, "T*", &PDFOp_Newline);
        CGPDFOperatorTableSetCallback(table, "ET", &PDFOp_Newline);
    });
    return table;
}

#pragma mark - PDFDoc Implementation

@interface PDFDoc ()
@property (nonatomic, strong) NSMutableArray<NSValue *> *trims;
@property (nonatomic, copy) NSString *cacheKey;
@end

@implementation PDFDoc {
    CGPDFDocumentRef _pdf;
    NSLock *_pdfLock;
    NSMutableArray<NSValue *> *_pageSizesCache;
    NSArray<PDFOutlineItem *> *_cachedOutline;
    BOOL _trimsLoaded;
}

+ (dispatch_queue_t)renderQueue {
    static dispatch_queue_t q;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.pdfnotes.render", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(q, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    });
    return q;
}

+ (dispatch_queue_t)utilityQueue {
    static dispatch_queue_t q;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.pdfnotes.utility", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(q, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
    });
    return q;
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = [path copy];
        _pdfLock = [[NSLock alloc] init];
        _trims = [NSMutableArray array];
        _pageSizesCache = [NSMutableArray array];

        if (path.length > 0) {
            NSURL *url = [NSURL fileURLWithPath:path];
            _pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)url);
        }

        if (_pdf) {
            _isEncrypted = CGPDFDocumentIsEncrypted(_pdf);
            if (_isEncrypted && !CGPDFDocumentIsUnlocked(_pdf)) {
                CGPDFDocumentUnlockWithPassword(_pdf, "");
            }
            _isLocked = (_isEncrypted && !CGPDFDocumentIsUnlocked(_pdf));
            if (!_isLocked) {
                [self setupPagesAndCacheKey];
            }
        }
    }
    return self;
}

- (void)setupPagesAndCacheKey {
    [_pdfLock lock];
    _pageCount = _pdf ? (NSInteger)CGPDFDocumentGetNumberOfPages(_pdf) : 0;
    [_pdfLock unlock];

    [_trims removeAllObjects];
    [_pageSizesCache removeAllObjects];
    for (NSInteger i = 0; i < _pageCount; i++) {
        [_trims addObject:[NSValue valueWithCGRect:CGRectMake(0.0f, 0.0f, 1.0f, 1.0f)]];
        [_pageSizesCache addObject:[NSValue valueWithCGSize:CGSizeZero]];
    }

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:_path error:NULL];
    id fileSize = attrs[NSFileSize] ?: @0;
    id modDate = [attrs[NSFileModificationDate] description] ?: @"";
    _cacheKey = [NSString stringWithFormat:@"%@|%@|%@", _path ?: @"", fileSize, modDate];
    _trimsLoaded = [self loadCachedTrims];
}

- (BOOL)unlockWithPassword:(NSString *)password {
    if (!_pdf) return NO;
    [_pdfLock lock];
    const char *utf8 = [password UTF8String] ?: "";
    BOOL ok = CGPDFDocumentUnlockWithPassword(_pdf, utf8);
    [_pdfLock unlock];
    if (ok) {
        _isLocked = NO;
        [self setupPagesAndCacheKey];
    }
    return ok;
}

- (void)dealloc {
    [_pdfLock lock];
    if (_pdf) {
        CGPDFDocumentRelease(_pdf);
        _pdf = NULL;
    }
    [_pdfLock unlock];
}

#pragma mark - Geometry & Trim Cache (100% DJB2 Backward Compatible)

- (CGSize)pageSizeAtIndex:(NSInteger)index {
    if (!_pdf || _isLocked || index < 0 || index >= _pageCount) {
        return CGSizeMake(612.0f, 792.0f);
    }

    @synchronized (_pageSizesCache) {
        if ((NSUInteger)index < _pageSizesCache.count) {
            CGSize cached = [_pageSizesCache[(NSUInteger)index] CGSizeValue];
            if (cached.width > 1.0f && cached.height > 1.0f) {
                return cached;
            }
        }
    }

    CGSize result = CGSizeMake(612.0f, 792.0f);
    [_pdfLock lock];
    CGPDFPageRef page = CGPDFDocumentGetPage(_pdf, (size_t)(index + 1));
    if (page) {
        CGRect box = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
        if (box.size.width <= 1.0f || box.size.height <= 1.0f) {
            box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
        }
        int rot = CGPDFPageGetRotationAngle(page);
        if (rot == 90 || rot == 270 || rot == -90) {
            result = CGSizeMake(box.size.height, box.size.width);
        } else {
            result = CGSizeMake(box.size.width, box.size.height);
        }
        if (!isfinite(result.width) || !isfinite(result.height) ||
            result.width <= 1.0f || result.height <= 1.0f) {
            result = CGSizeMake(612.0f, 792.0f);
        }
    }
    [_pdfLock unlock];

    @synchronized (_pageSizesCache) {
        if ((NSUInteger)index < _pageSizesCache.count) {
            _pageSizesCache[(NSUInteger)index] = [NSValue valueWithCGSize:result];
        }
    }
    return result;
}

- (CGRect)trimAtIndex:(NSInteger)index {
    if (index < 0) return CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
    @synchronized (_trims) {
        if ((NSUInteger)index < _trims.count) {
            CGRect r = [_trims[(NSUInteger)index] CGRectValue];
            if (r.size.width > 0.005f && r.size.height > 0.005f &&
                isfinite(r.origin.x) && isfinite(r.origin.y) &&
                isfinite(r.size.width) && isfinite(r.size.height)) {
                return r;
            }
        }
    }
    return CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
}

- (CGRect)trimAtIndex:(NSInteger)index autoTrim:(BOOL)autoTrim {
    if (!autoTrim) {
        return CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
    }
    return [self trimAtIndex:index];
}

- (NSString *)cacheFilePath {
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [caches stringByAppendingPathComponent:@"PDFNotesTrims"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    uint32_t h = 5381u;
    NSUInteger len = _cacheKey.length;
    for (NSUInteger i = 0; i < len; i++) {
        h = ((h << 5) + h) + (uint32_t)[_cacheKey characterAtIndex:i];
    }
    NSString *name = [NSString stringWithFormat:@"%lu.plist", (unsigned long)h];
    return [dir stringByAppendingPathComponent:name];
}

- (BOOL)hasCachedTrims {
    return _trimsLoaded;
}

- (BOOL)loadCachedTrims {
    if (_pageCount <= 0) return NO;
    NSArray *arr = [NSArray arrayWithContentsOfFile:[self cacheFilePath]];
    if (![arr isKindOfClass:[NSArray class]] || (NSInteger)arr.count != _pageCount) {
        return NO;
    }

    NSMutableArray<NSValue *> *loaded = [NSMutableArray arrayWithCapacity:(NSUInteger)_pageCount];
    for (NSInteger i = 0; i < _pageCount; i++) {
        NSDictionary *d = arr[(NSUInteger)i];
        if (![d isKindOfClass:[NSDictionary class]]) return NO;
        CGFloat x = [d[@"x"] floatValue];
        CGFloat y = [d[@"y"] floatValue];
        CGFloat w = [d[@"w"] floatValue];
        CGFloat h = [d[@"h"] floatValue];
        if (!isfinite(x) || !isfinite(y) || !isfinite(w) || !isfinite(h) || w <= 0.0f || h <= 0.0f) {
            return NO;
        }
        [loaded addObject:[NSValue valueWithCGRect:CGRectMake(x, y, w, h)]];
    }

    @synchronized (_trims) {
        _trims = loaded;
    }
    return YES;
}

- (void)saveCachedTrims {
    NSMutableArray *out = nil;
    @synchronized (_trims) {
        out = [NSMutableArray arrayWithCapacity:_trims.count];
        for (NSValue *v in _trims) {
            CGRect r = [v CGRectValue];
            [out addObject:@{
                @"x": @((float)r.origin.x),
                @"y": @((float)r.origin.y),
                @"w": @((float)r.size.width),
                @"h": @((float)r.size.height),
            }];
        }
    }
    [out writeToFile:[self cacheFilePath] atomically:YES];
}

- (CGRect)computeTrimForPage:(NSInteger)index {
    @autoreleasepool {
        if (!_pdf || _isLocked || index < 0 || index >= _pageCount) {
            return CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
        }

        CGSize pageSz = [self pageSizeAtIndex:index];
        PDFRasterSize sample = PDFTrimSampleSize(pageSz.width, pageSz.height);
        // Too few samples on the short axis to distinguish content from margins.
        if (sample.width < 8 || sample.height < 8) {
            return CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
        }

        int w = sample.width, h = sample.height;
        size_t bytesPerRow = (size_t)w * 4u;
        NSMutableData *buf = [NSMutableData dataWithLength:bytesPerRow * (size_t)h];
        if (!buf) return CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);

        uint8_t *pixels = (uint8_t *)[buf mutableBytes];

        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(pixels,
                                                 (size_t)w,
                                                 (size_t)h,
                                                 8,
                                                 bytesPerRow,
                                                 cs,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(cs);
        if (!ctx) return CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);

        CGContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
        CGContextFillRect(ctx, CGRectMake(0.0f, 0.0f, (CGFloat)w, (CGFloat)h));

        // CGBitmapContext has bottom-left origin; draw PDF upright into bottom-left rect (0, 0, w, h)
        [_pdfLock lock];
        CGPDFPageRef page = CGPDFDocumentGetPage(_pdf, (size_t)(index + 1));
        if (page) {
            CGContextSaveGState(ctx);
            CGContextScaleCTM(ctx, w / pageSz.width, h / pageSz.height);
            CGAffineTransform pdfXform = CGPDFPageGetDrawingTransform(page,
                                                                      kCGPDFCropBox,
                                                                      CGRectMake(0.0f, 0.0f, pageSz.width, pageSz.height),
                                                                      0,
                                                                      YES);
            CGContextConcatCTM(ctx, pdfXform);
            CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
            CGContextDrawPDFPage(ctx, page);
            CGContextRestoreGState(ctx);
        }
        [_pdfLock unlock];
        CGContextRelease(ctx);

        // Note: row 0 in CGBitmapContext memory is the TOP row of the image!
        int minX = w, maxX = -1;
        int minY = h, maxY = -1;
        for (int y = 0; y < h; y++) {
            const uint8_t *row = pixels + (size_t)y * bytesPerRow;
            for (int x = 0; x < w; x++) {
                const uint8_t *px = row + (size_t)x * 4u;
                if (px[0] < 248u || px[1] < 248u || px[2] <= 247u) {
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
            }
        }

        if (maxX < 0 || maxY < 0) {
            return CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
        }

        float x0 = MAX(0.0f, ((float)minX / (float)w) - 0.015f);
        float x1 = MIN(1.0f, ((float)(maxX + 1) / (float)w) + 0.015f);
        float y0 = MAX(0.0f, ((float)minY / (float)h) - 0.015f);
        float y1 = MIN(1.0f, ((float)(maxY + 1) / (float)h) + 0.015f);

        float tw = x1 - x0;
        float th = y1 - y0;

        if (tw < 0.08f) {
            float midX = (x0 + x1) * 0.5f;
            x0 = MAX(0.0f, MIN(1.0f - 0.08f, midX - 0.04f));
            tw = 0.08f;
        }
        if (th < 0.05f) {
            float midY = (y0 + y1) * 0.5f;
            y0 = MAX(0.0f, MIN(1.0f - 0.05f, midY - 0.025f));
            th = 0.05f;
        }

        return CGRectMake(x0, y0, tw, th);
    }
}

- (void)prepareTrimsWithCancelToken:(PDFCancelToken *)token
                           progress:(void (^)(float progress))progressBlock {
    if (_trimsLoaded || [self loadCachedTrims]) {
        _trimsLoaded = YES;
        if (progressBlock) progressBlock(1.0f);
        return;
    }
    if (_pageCount <= 0) {
        if (progressBlock) progressBlock(1.0f);
        return;
    }

    for (NSInteger i = 0; i < _pageCount; i++) {
        if (token && token.isCancelled) {
            return;
        }
        CGRect t = [self computeTrimForPage:i];
        @synchronized (_trims) {
            if ((NSUInteger)i < _trims.count) {
                _trims[(NSUInteger)i] = [NSValue valueWithCGRect:t];
            }
        }
        if (progressBlock) {
            progressBlock((float)(i + 1) / (float)_pageCount);
        }
    }

    if (!token || !token.isCancelled) {
        _trimsLoaded = YES;
        [self saveCachedTrims];
    }
}

#pragma mark - Page & Thumbnail Rendering (iPad 3 Safe)

- (UIImage *)renderPage:(NSInteger)index
                 region:(CGRect)region
             pixelWidth:(CGFloat)pixelWidth
                  theme:(PDFReadingTheme)theme {
    return [self renderPage:index region:region pixelWidth:pixelWidth maxSide:PDFPageMaxSide theme:theme];
}

- (UIImage *)renderPage:(NSInteger)index
                 region:(CGRect)region
             pixelWidth:(CGFloat)pixelWidth
                maxSide:(int)maxSide
                  theme:(PDFReadingTheme)theme {
    @autoreleasepool {
        if (!_pdf || _isLocked || index < 0 || index >= _pageCount) {
            return nil;
        }

        CGSize pageSz = [self pageSizeAtIndex:index];
        CGFloat regW = (region.size.width > 0.005f) ? region.size.width : 1.0f;
        CGFloat regH = (region.size.height > 0.005f) ? region.size.height : 1.0f;
        CGFloat cropW = pageSz.width * regW;
        CGFloat cropH = pageSz.height * regH;
        if (cropW < 1.0f || cropH < 1.0f) return nil;

        PDFRasterSize raster = PDFRasterFit(cropW, cropH, pixelWidth, maxSide, PDFPageMaxPixels);
        if (!raster.width || !raster.height) return nil;
        CGFloat pw = raster.width, ph = raster.height;

        CGSize ctxSize = CGSizeMake(pw, ph);
        UIGraphicsBeginImageContextWithOptions(ctxSize, YES, 1.0f);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        if (!ctx) {
            UIGraphicsEndImageContext();
            return nil;
        }

        CGRect fullRect = CGRectMake(0.0f, 0.0f, pw, ph);
        CGContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
        CGContextFillRect(ctx, fullRect);
        CGContextClipToRect(ctx, fullRect);

        [_pdfLock lock];
        CGPDFPageRef page = CGPDFDocumentGetPage(_pdf, (size_t)(index + 1));
        if (page) {
            CGContextSaveGState(ctx);
            CGFloat scaleX = pw / cropW, scaleY = ph / cropH;
            CGAffineTransform flipCrop = CGAffineTransformMake(scaleX,
                                                               0.0f,
                                                               0.0f,
                                                               -scaleY,
                                                               -scaleX * region.origin.x * pageSz.width,
                                                               scaleY * (1.0f - region.origin.y) * pageSz.height);
            CGContextConcatCTM(ctx, flipCrop);

            CGAffineTransform pdfXform = CGPDFPageGetDrawingTransform(page,
                                                                      kCGPDFCropBox,
                                                                      CGRectMake(0.0f, 0.0f, pageSz.width, pageSz.height),
                                                                      0,
                                                                      YES);
            CGContextConcatCTM(ctx, pdfXform);
            CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
            CGContextDrawPDFPage(ctx, page);
            CGContextRestoreGState(ctx);
        }
        [_pdfLock unlock];

        if (theme == PDFReadingThemeSepia) {
            CGContextSaveGState(ctx);
            CGContextSetBlendMode(ctx, kCGBlendModeMultiply);
            CGContextSetRGBFillColor(ctx, 0.965f, 0.925f, 0.840f, 1.0f);
            CGContextFillRect(ctx, fullRect);
            CGContextRestoreGState(ctx);
        } else if (theme == PDFReadingThemeNight) {
            CGContextSaveGState(ctx);
            CGContextSetBlendMode(ctx, kCGBlendModeDifference);
            CGContextSetRGBFillColor(ctx, 0.89f, 0.90f, 0.92f, 1.0f);
            CGContextFillRect(ctx, fullRect);
            CGContextRestoreGState(ctx);
        }

        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return img;
    }
}

- (UIImage *)renderThumbnailAtIndex:(NSInteger)index maxPixelSide:(CGFloat)maxPixelSide {
    if (!isfinite(maxPixelSide) || maxPixelSide < 1) return nil;
    int side = (int)MIN(maxPixelSide, PDFPageMaxSide);
    return [self renderPage:index region:CGRectMake(0, 0, 1, 1)
                 pixelWidth:side maxSide:side theme:PDFReadingThemePaper];
}

#pragma mark - PDF Outline (Table of Contents)

- (NSInteger)pageIndexForPageDictionary:(CGPDFDictionaryRef)targetDict {
    if (!targetDict || !_pdf) return NSNotFound;
    size_t count = CGPDFDocumentGetNumberOfPages(_pdf);
    for (size_t i = 1; i <= count; i++) {
        CGPDFPageRef p = CGPDFDocumentGetPage(_pdf, i);
        if (p && CGPDFPageGetDictionary(p) == targetDict) {
            return (NSInteger)(i - 1);
        }
    }
    return NSNotFound;
}

- (CGPDFArrayRef)findNamedDestInNameTree:(CGPDFDictionaryRef)node name:(const char *)targetName depth:(int)depth {
    if (!node || !targetName || depth > 16) return NULL;

    CGPDFArrayRef names = NULL;
    if (CGPDFDictionaryGetArray(node, "Names", &names) && names) {
        size_t n = CGPDFArrayGetCount(names);
        for (size_t i = 0; i + 1 < n; i += 2) {
            CGPDFStringRef keyStr = NULL;
            if (CGPDFArrayGetString(names, i, &keyStr) && keyStr) {
                const unsigned char *bytes = CGPDFStringGetBytePtr(keyStr);
                size_t len = CGPDFStringGetLength(keyStr);
                NSString *targetNS = @(targetName);
                NSData *targetData = [targetNS dataUsingEncoding:NSISOLatin1StringEncoding];
                if (bytes && targetData && targetData.length == len &&
                    [[NSData dataWithBytesNoCopy:(void *)bytes length:len freeWhenDone:NO] isEqualToData:targetData]) {
                    CGPDFArrayRef destArr = NULL;
                    if (CGPDFArrayGetArray(names, i + 1, &destArr)) return destArr;
                    CGPDFDictionaryRef destDict = NULL;
                    if (CGPDFArrayGetDictionary(names, i + 1, &destDict) && destDict) {
                        if (CGPDFDictionaryGetArray(destDict, "D", &destArr)) return destArr;
                    }
                }
            }
        }
    }

    CGPDFArrayRef kids = NULL;
    if (CGPDFDictionaryGetArray(node, "Kids", &kids) && kids) {
        size_t kCount = CGPDFArrayGetCount(kids);
        for (size_t i = 0; i < kCount; i++) {
            CGPDFDictionaryRef kid = NULL;
            if (CGPDFArrayGetDictionary(kids, i, &kid) && kid) {
                CGPDFArrayRef found = [self findNamedDestInNameTree:kid name:targetName depth:depth + 1];
                if (found) return found;
            }
        }
    }
    return NULL;
}

- (NSInteger)resolveDestObject:(CGPDFObjectRef)destObj catalog:(CGPDFDictionaryRef)catalog {
    if (!destObj) return NSNotFound;
    CGPDFObjectType type = CGPDFObjectGetType(destObj);
    CGPDFArrayRef destArray = NULL;

    if (type == kCGPDFObjectTypeArray) {
        CGPDFObjectGetValue(destObj, kCGPDFObjectTypeArray, &destArray);
    } else if (type == kCGPDFObjectTypeName || type == kCGPDFObjectTypeString) {
        const char *nameC = NULL;
        NSData *tempBuf = nil;
        if (type == kCGPDFObjectTypeName) {
            CGPDFObjectGetValue(destObj, kCGPDFObjectTypeName, &nameC);
        } else {
            CGPDFStringRef s = NULL;
            if (CGPDFObjectGetValue(destObj, kCGPDFObjectTypeString, &s) && s) {
                size_t len = CGPDFStringGetLength(s);
                const unsigned char *ptr = CGPDFStringGetBytePtr(s);
                if (ptr && len > 0) {
                    NSMutableData *d = [NSMutableData dataWithBytes:ptr length:len];
                    char zero = 0;
                    [d appendBytes:&zero length:1];
                    tempBuf = d;
                    nameC = (const char *)tempBuf.bytes;
                }
            }
        }
        if (nameC && catalog) {
            CGPDFDictionaryRef destsDict = NULL;
            if (CGPDFDictionaryGetDictionary(catalog, "Dests", &destsDict) && destsDict) {
                if (!CGPDFDictionaryGetArray(destsDict, nameC, &destArray)) {
                    CGPDFDictionaryRef sub = NULL;
                    if (CGPDFDictionaryGetDictionary(destsDict, nameC, &sub) && sub) {
                        CGPDFDictionaryGetArray(sub, "D", &destArray);
                    }
                }
            }
            if (!destArray) {
                CGPDFDictionaryRef namesDict = NULL;
                if (CGPDFDictionaryGetDictionary(catalog, "Names", &namesDict) && namesDict) {
                    CGPDFDictionaryRef tree = NULL;
                    if (CGPDFDictionaryGetDictionary(namesDict, "Dests", &tree) && tree) {
                        destArray = [self findNamedDestInNameTree:tree name:nameC depth:0];
                    }
                }
            }
        }
    }

    if (destArray && CGPDFArrayGetCount(destArray) > 0) {
        CGPDFDictionaryRef pageDict = NULL;
        if (CGPDFArrayGetDictionary(destArray, 0, &pageDict) && pageDict) {
            return [self pageIndexForPageDictionary:pageDict];
        }
        CGPDFInteger pageNum = 0;
        if (CGPDFArrayGetInteger(destArray, 0, &pageNum)) {
            if (pageNum >= 0 && pageNum < _pageCount) return (NSInteger)pageNum;
        }
    }
    return NSNotFound;
}

- (void)collectOutlineNode:(CGPDFDictionaryRef)firstItem
                   catalog:(CGPDFDictionaryRef)catalog
                     level:(NSInteger)level
                      into:(NSMutableArray<PDFOutlineItem *> *)outItems
                   visited:(NSMutableSet<NSValue *> *)visited {
    CGPDFDictionaryRef cur = firstItem;
    while (cur && outItems.count < 800) {
        NSValue *ptrVal = [NSValue valueWithPointer:cur];
        if ([visited containsObject:ptrVal]) break;
        [visited addObject:ptrVal];

        CGPDFStringRef titleStr = NULL;
        NSString *title = nil;
        if (CGPDFDictionaryGetString(cur, "Title", &titleStr) && titleStr) {
            CFStringRef cf = CGPDFStringCopyTextString(titleStr);
            if (cf) {
                title = [(__bridge NSString *)cf stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                CFRelease(cf);
            }
        }

        NSInteger pageIdx = NSNotFound;
        CGPDFObjectRef destObj = NULL;
        if (CGPDFDictionaryGetObject(cur, "Dest", &destObj) && destObj) {
            pageIdx = [self resolveDestObject:destObj catalog:catalog];
        } else {
            CGPDFDictionaryRef action = NULL;
            if (CGPDFDictionaryGetDictionary(cur, "A", &action) && action) {
                const char *sType = NULL;
                if (CGPDFDictionaryGetName(action, "S", &sType) && sType && [@(sType) isEqualToString:@"GoTo"]) {
                    CGPDFObjectRef dObj = NULL;
                    if (CGPDFDictionaryGetObject(action, "D", &dObj) && dObj) {
                        pageIdx = [self resolveDestObject:dObj catalog:catalog];
                    }
                }
            }
        }

        if (title.length > 0 && pageIdx != NSNotFound && pageIdx >= 0 && pageIdx < _pageCount) {
            PDFOutlineItem *item = [[PDFOutlineItem alloc] init];
            item.title = title;
            item.pageIndex = pageIdx;
            item.level = MIN(level, 5);
            [outItems addObject:item];
        }

        CGPDFDictionaryRef child = NULL;
        if (CGPDFDictionaryGetDictionary(cur, "First", &child) && child) {
            [self collectOutlineNode:child catalog:catalog level:level + 1 into:outItems visited:visited];
        }

        CGPDFDictionaryRef next = NULL;
        if (CGPDFDictionaryGetDictionary(cur, "Next", &next) && next) {
            cur = next;
        } else {
            break;
        }
    }
}

- (NSArray<PDFOutlineItem *> *)outlineItems {
    if (_cachedOutline) return _cachedOutline;
    if (!_pdf || _isLocked) return @[];

    NSMutableArray<PDFOutlineItem *> *items = [NSMutableArray array];
    [_pdfLock lock];
    CGPDFDictionaryRef catalog = CGPDFDocumentGetCatalog(_pdf);
    if (catalog) {
        CGPDFDictionaryRef outlines = NULL;
        if (CGPDFDictionaryGetDictionary(catalog, "Outlines", &outlines) && outlines) {
            CGPDFDictionaryRef first = NULL;
            if (CGPDFDictionaryGetDictionary(outlines, "First", &first) && first) {
                NSMutableSet<NSValue *> *visited = [NSMutableSet set];
                [self collectOutlineNode:first catalog:catalog level:0 into:items visited:visited];
            }
        }
    }
    [_pdfLock unlock];

    _cachedOutline = [items copy];
    return _cachedOutline;
}

#pragma mark - In-PDF Text Extraction & Search

- (NSString *)extractTextForPage:(NSInteger)index {
    if (!_pdf || _isLocked || index < 0 || index >= _pageCount) return @"";
    @autoreleasepool {
        NSMutableString *buffer = [NSMutableString string];
        [_pdfLock lock];
        CGPDFPageRef page = CGPDFDocumentGetPage(_pdf, (size_t)(index + 1));
        if (page) {
            CGPDFContentStreamRef stream = CGPDFContentStreamCreateWithPage(page);
            if (stream) {
                PDFTextScanCtx scanCtx = { .buffer = buffer };
                CGPDFScannerRef scanner = CGPDFScannerCreate(stream, PDFSharedOperatorTable(), &scanCtx);
                if (scanner) {
                    CGPDFScannerScan(scanner);
                    CGPDFScannerRelease(scanner);
                }
                CGPDFContentStreamRelease(stream);
            }
        }
        [_pdfLock unlock];
        return [buffer copy];
    }
}

- (NSArray<PDFSearchMatch *> *)searchForQuery:(NSString *)query
                                  cancelToken:(PDFCancelToken *)token
                                     progress:(void (^)(NSInteger scanned, NSInteger total))progressBlock {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || _pageCount <= 0) return @[];

    NSMutableArray<PDFSearchMatch *> *matches = [NSMutableArray array];
    for (NSInteger i = 0; i < _pageCount; i++) {
        if (token && token.isCancelled) return @[];
        @autoreleasepool {
            NSString *pageText = [self extractTextForPage:i];
            if (pageText.length > 0) {
                NSRange searchRange = NSMakeRange(0, pageText.length);
                NSUInteger pageHits = 0;
                while (searchRange.location < pageText.length && pageHits < 5) {
                    NSRange found = [pageText rangeOfString:trimmed
                                                    options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)
                                                      range:searchRange];
                    if (found.location == NSNotFound) break;

                    NSInteger start = MAX(0, (NSInteger)found.location - 32);
                    NSInteger end = MIN((NSInteger)pageText.length, (NSInteger)(found.location + found.length + 48));
                    NSString *rawSnippet = [pageText substringWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))];
                    NSArray *parts = [rawSnippet componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    NSMutableArray *nonEmpty = [NSMutableArray array];
                    for (NSString *p in parts) {
                        if (p.length > 0) [nonEmpty addObject:p];
                    }
                    NSString *cleanSnippet = [nonEmpty componentsJoinedByString:@" "];
                    if (start > 0) cleanSnippet = [@"…" stringByAppendingString:cleanSnippet];
                    if (end < (NSInteger)pageText.length) cleanSnippet = [cleanSnippet stringByAppendingString:@"…"];

                    PDFSearchMatch *m = [[PDFSearchMatch alloc] init];
                    m.pageIndex = i;
                    m.snippet = cleanSnippet;
                    [matches addObject:m];
                    pageHits++;

                    searchRange.location = found.location + MAX((NSUInteger)1, found.length);
                    searchRange.length = pageText.length - searchRange.location;
                }
            }
        }
        if (progressBlock && ((i % 4 == 0) || i == _pageCount - 1)) {
            progressBlock(i + 1, _pageCount);
        }
    }
    return matches;
}

#pragma mark - Memory-Safe Streaming Vector PDF Export

- (BOOL)exportAnnotatedPDFToPath:(NSString *)outputPath
                           store:(AnnotationStore *)store
                     cancelToken:(PDFCancelToken *)token
                        progress:(void (^)(float progress))progressBlock
                           error:(NSError **)outError {
    if (!_pdf || _isLocked || _pageCount <= 0 || outputPath.length == 0) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"com.pdfnotes.export"
                                            code:1
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Invalid or locked PDF document." }];
        }
        return NO;
    }

    NSString *tempPath = [outputPath stringByAppendingString:@".exporting.tmp"];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:NULL];

    BOOL began = UIGraphicsBeginPDFContextToFile(tempPath, CGRectZero, @{
        (NSString *)kCGPDFContextCreator: @"PDF Notes 3.0 for iPad",
    });
    if (!began) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"com.pdfnotes.export"
                                            code:2
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Could not create temporary export file." }];
        }
        return NO;
    }

    BOOL cancelled = NO;
    for (NSInteger i = 0; i < _pageCount; i++) {
        if (token && token.isCancelled) {
            cancelled = YES;
            break;
        }
        @autoreleasepool {
            CGSize pageSz = [self pageSizeAtIndex:i];
            CGRect pageBounds = CGRectMake(0.0f, 0.0f, pageSz.width, pageSz.height);
            UIGraphicsBeginPDFPageWithInfo(pageBounds, nil);
            CGContextRef ctx = UIGraphicsGetCurrentContext();

            // 1. Draw original vector PDF page (preserves sharp text, vectors & tiny file size!)
            [_pdfLock lock];
            CGPDFPageRef page = CGPDFDocumentGetPage(_pdf, (size_t)(i + 1));
            if (page && ctx) {
                CGContextSaveGState(ctx);
                CGContextTranslateCTM(ctx, 0.0f, pageSz.height);
                CGContextScaleCTM(ctx, 1.0f, -1.0f);
                CGAffineTransform pdfXform = CGPDFPageGetDrawingTransform(page,
                                                                          kCGPDFCropBox,
                                                                          pageBounds,
                                                                          0,
                                                                          YES);
                CGContextConcatCTM(ctx, pdfXform);
                CGContextDrawPDFPage(ctx, page);
                CGContextRestoreGState(ctx);
            }
            [_pdfLock unlock];

            // 2. Overlay vector strokes with isolated GState & Multiply blend mode for highlighters
            NSArray<Stroke *> *strokes = store ? [store strokesForPage:i] : @[];
            for (Stroke *s in strokes) {
                if (!ctx || s.points.count == 0) continue;
                CGContextSaveGState(ctx);
                if (s.kind == StrokeKindMarker) {
                    CGContextSetBlendMode(ctx, kCGBlendModeMultiply);
                }
                CGContextSetAlpha(ctx, [s alpha]);
                [s.color setStroke];
                UIBezierPath *path = [s pathWithPointMap:^CGPoint(CGPoint np) {
                    return CGPointMake(np.x * pageSz.width, np.y * pageSz.height);
                }];
                path.lineWidth = MAX(0.5f, s.widthFraction * pageSz.width);
                [path stroke];
                CGContextRestoreGState(ctx);
            }

            // 3. Overlay vector TextNotes
            NSArray<TextNote *> *notes = store ? [store notesForPage:i] : @[];
            for (TextNote *n in notes) {
                if (!ctx || n.text.length == 0) continue;
                CGContextSaveGState(ctx);
                CGFloat nx = n.normalizedPosition.x * pageSz.width;
                CGFloat ny = n.normalizedPosition.y * pageSz.height;
                CGFloat maxW = MIN(190.0f, MAX(100.0f, pageSz.width - nx - 12.0f));
                UIFont *font = [UIFont systemFontOfSize:MAX(9.0f, n.fontSize * (pageSz.width / 612.0f))];
                NSDictionary *attrs = @{
                    NSFontAttributeName: font,
                    NSForegroundColorAttributeName: [UIColor colorWithWhite:0.12f alpha:1.0f],
                };
                CGRect textBounds = [n.text boundingRectWithSize:CGSizeMake(maxW - 14.0f, 400.0f)
                                                         options:NSStringDrawingUsesLineFragmentOrigin
                                                      attributes:attrs
                                                         context:nil];
                CGRect cardRect = CGRectMake(nx, ny, ceilf((float)textBounds.size.width) + 14.0f, ceilf((float)textBounds.size.height) + 12.0f);
                UIBezierPath *card = [UIBezierPath bezierPathWithRoundedRect:cardRect cornerRadius:5.0f];
                [[n.color colorWithAlphaComponent:0.93f] setFill];
                [card fill];
                [[UIColor colorWithWhite:0.0f alpha:0.22f] setStroke];
                card.lineWidth = 0.8f;
                [card stroke];
                [n.text drawInRect:CGRectInset(cardRect, 7.0f, 6.0f) withAttributes:attrs];
                CGContextRestoreGState(ctx);
            }
        }
        if (progressBlock) {
            progressBlock((float)(i + 1) / (float)_pageCount);
        }
    }

    UIGraphicsEndPDFContext();

    NSFileManager *fm = [NSFileManager defaultManager];
    if (cancelled) {
        [fm removeItemAtPath:tempPath error:NULL];
        if (outError) {
            *outError = [NSError errorWithDomain:@"com.pdfnotes.export"
                                            code:3
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Export cancelled." }];
        }
        return NO;
    }

    [fm removeItemAtPath:outputPath error:NULL];
    NSError *moveErr = nil;
    if (![fm moveItemAtPath:tempPath toPath:outputPath error:&moveErr]) {
        [fm removeItemAtPath:tempPath error:NULL];
        if (outError) *outError = moveErr;
        return NO;
    }
    return YES;
}

#pragma mark - Built-in Notebook PDF Creator

+ (BOOL)createNotebookPDFAtPath:(NSString *)outputPath
                  templateStyle:(PDFNotebookTemplate)style
                      pageCount:(NSInteger)pageCount
                          error:(NSError **)outError {
    if (outputPath.length == 0 || pageCount <= 0) return NO;
    pageCount = MIN(pageCount, 200);

    CGRect pageRect = CGRectMake(0.0f, 0.0f, 612.0f, 792.0f); // Standard US Letter
    if (!UIGraphicsBeginPDFContextToFile(outputPath, pageRect, @{
            (NSString *)kCGPDFContextCreator: @"PDF Notes 3.0 Notebook Generator",
        })) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"com.pdfnotes.notebook"
                                            code:1
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Could not create notebook PDF." }];
        }
        return NO;
    }

    for (NSInteger p = 0; p < pageCount; p++) {
        @autoreleasepool {
            UIGraphicsBeginPDFPageWithInfo(pageRect, nil);
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            if (!ctx) continue;

            // Warm off-white paper
            [[UIColor colorWithRed:0.996f green:0.994f blue:0.985f alpha:1.0f] setFill];
            CGContextFillRect(ctx, pageRect);

            UIColor *lineColor = [UIColor colorWithRed:0.74f green:0.83f blue:0.92f alpha:0.75f];
            UIColor *marginColor = [UIColor colorWithRed:0.91f green:0.58f blue:0.60f alpha:0.65f];

            if (style == PDFNotebookTemplateRuled) {
                [lineColor setStroke];
                CGContextSetLineWidth(ctx, 0.65f);
                for (CGFloat y = 72.0f; y <= 748.0f; y += 24.0f) {
                    CGContextMoveToPoint(ctx, 36.0f, y);
                    CGContextAddLineToPoint(ctx, 576.0f, y);
                }
                CGContextStrokePath(ctx);

                [marginColor setStroke];
                CGContextSetLineWidth(ctx, 0.85f);
                CGContextMoveToPoint(ctx, 72.0f, 36.0f);
                CGContextAddLineToPoint(ctx, 72.0f, 756.0f);
                CGContextStrokePath(ctx);
            } else if (style == PDFNotebookTemplateGrid) {
                [lineColor setStroke];
                CGContextSetLineWidth(ctx, 0.5f);
                CGFloat step = 18.0f;
                for (CGFloat x = 36.0f; x <= 576.0f + 0.1f; x += step) {
                    CGContextMoveToPoint(ctx, x, 36.0f);
                    CGContextAddLineToPoint(ctx, x, 756.0f);
                }
                for (CGFloat y = 36.0f; y <= 756.0f + 0.1f; y += step) {
                    CGContextMoveToPoint(ctx, 36.0f, y);
                    CGContextAddLineToPoint(ctx, 576.0f, y);
                }
                CGContextStrokePath(ctx);
            } else if (style == PDFNotebookTemplateDotted) {
                [[UIColor colorWithRed:0.62f green:0.68f blue:0.76f alpha:0.75f] setFill];
                CGFloat step = 18.0f;
                for (CGFloat y = 42.0f; y <= 750.0f; y += step) {
                    for (CGFloat x = 42.0f; x <= 570.0f; x += step) {
                        CGContextFillEllipseInRect(ctx, CGRectMake(x - 0.9f, y - 0.9f, 1.8f, 1.8f));
                    }
                }
            } else if (style == PDFNotebookTemplateCornell) {
                [lineColor setStroke];
                CGContextSetLineWidth(ctx, 0.65f);
                // Notes area ruled lines
                for (CGFloat y = 96.0f; y <= 636.0f; y += 24.0f) {
                    CGContextMoveToPoint(ctx, 180.0f, y);
                    CGContextAddLineToPoint(ctx, 576.0f, y);
                }
                CGContextStrokePath(ctx);

                // Header, cue divider, and summary divider
                [marginColor setStroke];
                CGContextSetLineWidth(ctx, 1.0f);
                CGContextMoveToPoint(ctx, 36.0f, 72.0f);
                CGContextAddLineToPoint(ctx, 576.0f, 72.0f);
                CGContextMoveToPoint(ctx, 180.0f, 72.0f);
                CGContextAddLineToPoint(ctx, 180.0f, 648.0f);
                CGContextMoveToPoint(ctx, 36.0f, 648.0f);
                CGContextAddLineToPoint(ctx, 576.0f, 648.0f);
                CGContextStrokePath(ctx);
            }
        }
    }

    UIGraphicsEndPDFContext();
    return YES;
}

@end
