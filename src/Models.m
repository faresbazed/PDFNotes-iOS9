#import "Models.h"
#import <math.h>

static inline CGFloat PDFSafeFloat(CGFloat v, CGFloat fallback, CGFloat minVal, CGFloat maxVal) {
    if (!isfinite(v)) return fallback;
    if (v < minVal) return minVal;
    if (v > maxVal) return maxVal;
    return v;
}

static void PDFExtractRGB(UIColor *color, CGFloat *outR, CGFloat *outG, CGFloat *outB) {
    CGFloat r = 0.0f, g = 0.0f, b = 0.0f, a = 1.0f;
    if (color && [color getRed:&r green:&g blue:&b alpha:&a]) {
        *outR = PDFSafeFloat(r, 0.0f, 0.0f, 1.0f);
        *outG = PDFSafeFloat(g, 0.0f, 0.0f, 1.0f);
        *outB = PDFSafeFloat(b, 0.0f, 0.0f, 1.0f);
        return;
    }
    CGFloat w = 0.0f;
    if (color && [color getWhite:&w alpha:&a]) {
        w = PDFSafeFloat(w, 0.0f, 0.0f, 1.0f);
        *outR = w;
        *outG = w;
        *outB = w;
        return;
    }
    if (color) {
        CGColorRef cg = color.CGColor;
        size_t n = CGColorGetNumberOfComponents(cg);
        const CGFloat *comps = CGColorGetComponents(cg);
        if (comps && n >= 3) {
            *outR = PDFSafeFloat(comps[0], 0.0f, 0.0f, 1.0f);
            *outG = PDFSafeFloat(comps[1], 0.0f, 0.0f, 1.0f);
            *outB = PDFSafeFloat(comps[2], 0.0f, 0.0f, 1.0f);
            return;
        } else if (comps && n >= 1) {
            CGFloat gray = PDFSafeFloat(comps[0], 0.0f, 0.0f, 1.0f);
            *outR = gray;
            *outG = gray;
            *outB = gray;
            return;
        }
    }
    *outR = 0.0f;
    *outG = 0.0f;
    *outB = 0.0f;
}

#pragma mark - Stroke

@implementation Stroke {
    CGRect _cachedBounds;
    BOOL _boundsValid;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _points = [NSMutableArray array];
        _color = [UIColor colorWithRed:0.08f green:0.08f blue:0.10f alpha:1.0f];
        _kind = StrokeKindPen;
        _widthFraction = 0.004f;
        _cachedBounds = CGRectNull;
        _boundsValid = NO;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    Stroke *copy = [[[self class] allocWithZone:zone] init];
    copy.kind = self.kind;
    copy.color = self.color;
    copy.widthFraction = self.widthFraction;
    copy.points = [NSMutableArray arrayWithArray:self.points];
    copy->_cachedBounds = _cachedBounds;
    copy->_boundsValid = _boundsValid;
    return copy;
}

- (CGFloat)alpha {
    return (self.kind == StrokeKindMarker) ? 0.38f : 1.0f;
}

- (void)invalidateBounds {
    _boundsValid = NO;
}

- (void)addNormalizedPoint:(CGPoint)pt {
    CGFloat x = PDFSafeFloat(pt.x, 0.0f, -0.5f, 1.5f);
    CGFloat y = PDFSafeFloat(pt.y, 0.0f, -0.5f, 1.5f);
    CGPoint clean = CGPointMake(x, y);
    [_points addObject:[NSValue valueWithCGPoint:clean]];
    if (_boundsValid && !CGRectIsNull(_cachedBounds)) {
        _cachedBounds = CGRectUnion(_cachedBounds, CGRectMake(clean.x, clean.y, 0.0f, 0.0f));
    } else {
        _boundsValid = NO;
    }
}

- (CGRect)normalizedBounds {
    if (_boundsValid) return _cachedBounds;
    if (_points.count == 0) {
        _cachedBounds = CGRectNull;
        _boundsValid = YES;
        return _cachedBounds;
    }
    CGPoint first = [_points[0] CGPointValue];
    CGFloat minX = first.x, maxX = first.x;
    CGFloat minY = first.y, maxY = first.y;
    for (NSValue *v in _points) {
        CGPoint p = [v CGPointValue];
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
    }
    CGFloat pad = MAX(_widthFraction, 0.002f);
    _cachedBounds = CGRectMake(minX - pad, minY - pad, (maxX - minX) + pad * 2.0f, (maxY - minY) + pad * 2.0f);
    _boundsValid = YES;
    return _cachedBounds;
}

- (NSDictionary *)toDictionary {
    CGFloat r = 0.0f, g = 0.0f, b = 0.0f;
    PDFExtractRGB(self.color, &r, &g, &b);

    NSMutableArray *pts = [NSMutableArray arrayWithCapacity:self.points.count];
    for (NSValue *v in self.points) {
        CGPoint p = [v CGPointValue];
        if (!isfinite(p.x) || !isfinite(p.y)) continue;
        [pts addObject:@{ @"x": @(p.x), @"y": @(p.y) }];
    }

    CGFloat wf = PDFSafeFloat(self.widthFraction, 0.004f, 0.0005f, 0.25f);
    return @{
        @"k":   @((NSInteger)self.kind),
        @"r":   @(r),
        @"g":   @(g),
        @"b":   @(b),
        @"w":   @(wf),
        @"pts": pts,
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    Stroke *s = [[Stroke alloc] init];
    NSInteger k = [dict[@"k"] integerValue];
    s.kind = (k == StrokeKindMarker) ? StrokeKindMarker : StrokeKindPen;

    if (dict[@"r"] != nil) {
        CGFloat r = PDFSafeFloat([dict[@"r"] floatValue], 0.0f, 0.0f, 1.0f);
        CGFloat g = PDFSafeFloat([dict[@"g"] floatValue], 0.0f, 0.0f, 1.0f);
        CGFloat b = PDFSafeFloat([dict[@"b"] floatValue], 0.0f, 0.0f, 1.0f);
        s.color = [UIColor colorWithRed:r green:g blue:b alpha:1.0f];
    } else {
        NSInteger c = [dict[@"c"] integerValue];
        s.color = (c == 1) ? [UIColor colorWithRed:0.85f green:0.10f blue:0.10f alpha:1.0f]
                : (c == 2) ? [UIColor colorWithRed:0.10f green:0.35f blue:0.95f alpha:1.0f]
                : (c == 3) ? [UIColor colorWithRed:0.95f green:0.80f blue:0.05f alpha:1.0f]
                : (c == 4) ? [UIColor colorWithRed:0.10f green:0.65f blue:0.20f alpha:1.0f]
                           : [UIColor blackColor];
    }

    CGFloat wf = [dict[@"w"] floatValue];
    if (!isfinite(wf) || wf <= 0.0f) {
        wf = (s.kind == StrokeKindMarker) ? 0.03f : 0.004f;
    }
    s.widthFraction = PDFSafeFloat(wf, 0.004f, 0.0005f, 0.25f);

    NSArray *rawPts = dict[@"pts"];
    if ([rawPts isKindOfClass:[NSArray class]]) {
        for (id item in rawPts) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                CGFloat x = [item[@"x"] floatValue];
                CGFloat y = [item[@"y"] floatValue];
                if (isfinite(x) && isfinite(y)) {
                    [s addNormalizedPoint:CGPointMake(x, y)];
                }
            } else if ([item isKindOfClass:[NSArray class]] && [item count] >= 2) {
                CGFloat x = [item[0] floatValue];
                CGFloat y = [item[1] floatValue];
                if (isfinite(x) && isfinite(y)) {
                    [s addNormalizedPoint:CGPointMake(x, y)];
                }
            }
        }
    }
    return s;
}

- (UIBezierPath *)pathWithPointMap:(CGPoint (^)(CGPoint))pointMap {
    UIBezierPath *path = [UIBezierPath bezierPath];
    path.lineCapStyle = kCGLineCapRound;
    path.lineJoinStyle = kCGLineJoinRound;

    NSUInteger count = self.points.count;
    if (count == 0 || !pointMap) return path;

    CGPoint p0 = pointMap([self.points[0] CGPointValue]);
    if (!isfinite(p0.x) || !isfinite(p0.y)) return path;

    if (count == 1) {
        [path moveToPoint:p0];
        [path addLineToPoint:CGPointMake(p0.x + 0.15f, p0.y)];
        return path;
    }

    // Check if all points are essentially stationary (tap with jitter)
    CGFloat maxDistSq = 0.0f;
    for (NSUInteger i = 1; i < count; i++) {
        CGPoint pi = pointMap([self.points[i] CGPointValue]);
        CGFloat dx = pi.x - p0.x;
        CGFloat dy = pi.y - p0.y;
        CGFloat dSq = dx * dx + dy * dy;
        if (dSq > maxDistSq) maxDistSq = dSq;
    }
    if (maxDistSq < 0.16f) {
        [path moveToPoint:p0];
        [path addLineToPoint:CGPointMake(p0.x + 0.15f, p0.y)];
        return path;
    }

    if (count == 2) {
        CGPoint p1 = pointMap([self.points[1] CGPointValue]);
        [path moveToPoint:p0];
        [path addLineToPoint:p1];
        return path;
    }

    // Smooth quadratic Bezier midpoint curve for silky handwriting on 60Hz iPad 3
    [path moveToPoint:p0];
    CGPoint prev = p0;
    for (NSUInteger i = 1; i < count - 1; i++) {
        CGPoint cur = pointMap([self.points[i] CGPointValue]);
        CGPoint mid = CGPointMake((prev.x + cur.x) * 0.5f, (prev.y + cur.y) * 0.5f);
        if (i == 1) {
            [path addLineToPoint:mid];
        } else {
            [path addQuadCurveToPoint:mid controlPoint:prev];
        }
        prev = cur;
    }
    CGPoint last = pointMap([self.points[count - 1] CGPointValue]);
    [path addQuadCurveToPoint:last controlPoint:prev];
    return path;
}

@end

#pragma mark - TextNote

@implementation TextNote

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = [[NSUUID UUID] UUIDString];
        _normalizedPosition = CGPointMake(0.15f, 0.15f);
        _text = @"";
        _color = [UIColor colorWithRed:0.98f green:0.84f blue:0.25f alpha:1.0f];
        _fontSize = 14.0f;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    TextNote *copy = [[[self class] allocWithZone:zone] init];
    copy.identifier = self.identifier;
    copy.normalizedPosition = self.normalizedPosition;
    copy.text = self.text;
    copy.color = self.color;
    copy.fontSize = self.fontSize;
    return copy;
}

- (NSDictionary *)toDictionary {
    CGFloat r = 0.98f, g = 0.84f, b = 0.25f;
    PDFExtractRGB(self.color, &r, &g, &b);
    return @{
        @"id": self.identifier ?: [[NSUUID UUID] UUIDString],
        @"x": @(PDFSafeFloat(self.normalizedPosition.x, 0.15f, 0.01f, 0.98f)),
        @"y": @(PDFSafeFloat(self.normalizedPosition.y, 0.15f, 0.01f, 0.98f)),
        @"text": self.text ?: @"",
        @"r": @(r),
        @"g": @(g),
        @"b": @(b),
        @"size": @(PDFSafeFloat(self.fontSize, 14.0f, 9.0f, 32.0f)),
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    TextNote *n = [[TextNote alloc] init];
    if ([dict[@"id"] isKindOfClass:[NSString class]] && [dict[@"id"] length] > 0) {
        n.identifier = dict[@"id"];
    }
    n.normalizedPosition = CGPointMake(PDFSafeFloat([dict[@"x"] floatValue], 0.15f, 0.01f, 0.98f),
                                       PDFSafeFloat([dict[@"y"] floatValue], 0.15f, 0.01f, 0.98f));
    n.text = [dict[@"text"] isKindOfClass:[NSString class]] ? dict[@"text"] : @"";
    if (dict[@"r"] != nil) {
        CGFloat r = PDFSafeFloat([dict[@"r"] floatValue], 0.98f, 0.0f, 1.0f);
        CGFloat g = PDFSafeFloat([dict[@"g"] floatValue], 0.84f, 0.0f, 1.0f);
        CGFloat b = PDFSafeFloat([dict[@"b"] floatValue], 0.25f, 0.0f, 1.0f);
        n.color = [UIColor colorWithRed:r green:g blue:b alpha:1.0f];
    }
    if (dict[@"size"] != nil) {
        n.fontSize = PDFSafeFloat([dict[@"size"] floatValue], 14.0f, 9.0f, 32.0f);
    }
    return n;
}

@end

#pragma mark - Page Edit Action (Undo / Redo Entry)

@interface PDFPageEditAction : NSObject
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, strong) NSArray<Stroke *> *beforeStrokes;
@property (nonatomic, strong) NSArray<Stroke *> *afterStrokes;
@property (nonatomic, strong) NSArray<TextNote *> *beforeNotes;
@property (nonatomic, strong) NSArray<TextNote *> *afterNotes;
@end

@implementation PDFPageEditAction
@end

#pragma mark - AnnotationStore

static const NSUInteger kMaxUndoSteps = 45;

@implementation AnnotationStore {
    NSMutableDictionary<NSString *, NSMutableArray<Stroke *> *> *_strokesByPage;
    NSMutableDictionary<NSString *, NSMutableArray<TextNote *> *> *_notesByPage;
    NSMutableIndexSet *_bookmarks;
    NSMutableArray<PDFPageEditAction *> *_undoStack;
    NSMutableArray<PDFPageEditAction *> *_redoStack;
    BOOL _dirty;
}

+ (NSString *)documentsDirectory {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [docs stringByResolvingSymlinksInPath] ?: [docs stringByStandardizingPath];
}

+ (NSString *)annotationsDirectory {
    NSString *dir = [[self documentsDirectory] stringByAppendingPathComponent:@"Annotations"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return dir;
}

+ (NSString *)annotationKeyForPDFPath:(NSString *)pdfPath {
    if (pdfPath.length == 0) return @"untitled.pdf";
    NSString *docs = [self documentsDirectory];
    NSString *resolved = [pdfPath stringByResolvingSymlinksInPath] ?: [pdfPath stringByStandardizingPath];
    NSString *prefix = [docs hasSuffix:@"/"] ? docs : [docs stringByAppendingString:@"/"];
    if ([resolved hasPrefix:prefix]) {
        NSString *rel = [resolved substringFromIndex:prefix.length];
        if (rel.length > 0) {
            return [rel stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
        }
    }
    return [resolved lastPathComponent];
}

+ (NSString *)annotationFilePathForPDFPath:(NSString *)pdfPath {
    NSString *key = [self annotationKeyForPDFPath:pdfPath];
    return [[self annotationsDirectory] stringByAppendingPathComponent:[key stringByAppendingPathExtension:@"plist"]];
}

+ (BOOL)hasSavedAnnotationsForPDFPath:(NSString *)pdfPath {
    NSString *path = [self annotationFilePathForPDFPath:pdfPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return NO;
    }
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![dict isKindOfClass:[NSDictionary class]]) return YES;
    NSDictionary *pages = [dict[@"pages"] isKindOfClass:[NSDictionary class]] ? dict[@"pages"] : nil;
    NSDictionary *notes = [dict[@"notes"] isKindOfClass:[NSDictionary class]] ? dict[@"notes"] : nil;
    NSArray *bms = [dict[@"bookmarks"] isKindOfClass:[NSArray class]] ? dict[@"bookmarks"] : nil;
    return (pages.count > 0 || notes.count > 0 || bms.count > 0);
}

+ (NSInteger)savedLastPageForPDFPath:(NSString *)pdfPath {
    NSString *path = [self annotationFilePathForPDFPath:pdfPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([dict isKindOfClass:[NSDictionary class]] && dict[@"lastPage"] != nil) {
            return [dict[@"lastPage"] integerValue];
        }
    }
    NSString *key = [NSString stringWithFormat:@"lastPage.%@", [self annotationKeyForPDFPath:pdfPath]];
    return [[NSUserDefaults standardUserDefaults] integerForKey:key];
}

+ (void)deleteAnnotationsForPath:(NSString *)itemPath isDirectory:(BOOL)isDirectory {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!isDirectory) {
        NSString *plistPath = [self annotationFilePathForPDFPath:itemPath];
        [fm removeItemAtPath:plistPath error:NULL];
        NSString *key = [self annotationKeyForPDFPath:itemPath];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[NSString stringWithFormat:@"lastPage.%@", key]];
        return;
    }

    NSString *docs = [self documentsDirectory];
    NSString *resolved = [itemPath stringByResolvingSymlinksInPath] ?: [itemPath stringByStandardizingPath];
    NSString *docsPrefix = [docs hasSuffix:@"/"] ? docs : [docs stringByAppendingString:@"/"];
    if (![resolved hasPrefix:docsPrefix]) return;

    NSString *relDir = [resolved substringFromIndex:docsPrefix.length];
    NSString *keyPrefix = [[relDir stringByReplacingOccurrencesOfString:@"/" withString:@"__"] stringByAppendingString:@"__"];
    NSString *annDir = [self annotationsDirectory];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:annDir error:NULL];
    for (NSString *f in files) {
        if ([f hasPrefix:keyPrefix]) {
            [fm removeItemAtPath:[annDir stringByAppendingPathComponent:f] error:NULL];
        }
    }
}

+ (void)moveAnnotationsFromPath:(NSString *)oldPath toPath:(NSString *)newPath isDirectory:(BOOL)isDirectory {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!isDirectory) {
        NSString *oldPlist = [self annotationFilePathForPDFPath:oldPath];
        NSString *newPlist = [self annotationFilePathForPDFPath:newPath];
        if (![oldPlist isEqualToString:newPlist] && [fm fileExistsAtPath:oldPlist]) {
            [fm removeItemAtPath:newPlist error:NULL];
            [fm moveItemAtPath:oldPlist toPath:newPlist error:NULL];
        }
        NSString *oldDef = [NSString stringWithFormat:@"lastPage.%@", [self annotationKeyForPDFPath:oldPath]];
        NSString *newDef = [NSString stringWithFormat:@"lastPage.%@", [self annotationKeyForPDFPath:newPath]];
        NSInteger last = [[NSUserDefaults standardUserDefaults] integerForKey:oldDef];
        if (last > 0) {
            [[NSUserDefaults standardUserDefaults] setInteger:last forKey:newDef];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:oldDef];
        }
        return;
    }

    NSString *docs = [self documentsDirectory];
    NSString *docsPrefix = [docs hasSuffix:@"/"] ? docs : [docs stringByAppendingString:@"/"];
    NSString *oldRes = [oldPath stringByResolvingSymlinksInPath] ?: [oldPath stringByStandardizingPath];
    NSString *newRes = [newPath stringByResolvingSymlinksInPath] ?: [newPath stringByStandardizingPath];
    if (![oldRes hasPrefix:docsPrefix] || ![newRes hasPrefix:docsPrefix]) return;

    NSString *oldRel = [oldRes substringFromIndex:docsPrefix.length];
    NSString *newRel = [newRes substringFromIndex:docsPrefix.length];
    NSString *oldKeyPrefix = [[oldRel stringByReplacingOccurrencesOfString:@"/" withString:@"__"] stringByAppendingString:@"__"];
    NSString *newKeyPrefix = [[newRel stringByReplacingOccurrencesOfString:@"/" withString:@"__"] stringByAppendingString:@"__"];

    NSString *annDir = [self annotationsDirectory];
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
}

- (instancetype)initWithPDFPath:(NSString *)pdfPath {
    self = [super init];
    if (self) {
        _pdfPath = [pdfPath copy];
        _annotationKey = [[[self class] annotationKeyForPDFPath:pdfPath] copy];
        _strokesByPage = [NSMutableDictionary dictionary];
        _notesByPage = [NSMutableDictionary dictionary];
        _bookmarks = [NSMutableIndexSet indexSet];
        _undoStack = [NSMutableArray array];
        _redoStack = [NSMutableArray array];
        _lastPageIndex = 0;

        [self loadFromDisk];

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(flushSynchronously) name:UIApplicationWillResignActiveNotification object:nil];
        [nc addObserver:self selector:@selector(flushSynchronously) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [nc addObserver:self selector:@selector(flushSynchronously) name:UIApplicationWillTerminateNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushSynchronously) object:nil];
    if (_dirty) {
        [self writeToDiskNow];
    }
}

- (NSString *)filePath {
    return [[[self class] annotationsDirectory] stringByAppendingPathComponent:[_annotationKey stringByAppendingPathExtension:@"plist"]];
}

- (void)loadFromDisk {
    NSString *primaryPath = [self filePath];
    NSString *loadedPath = primaryPath;
    NSData *data = [NSData dataWithContentsOfFile:primaryPath];

    if (!data && _pdfPath.length > 0) {
        // Legacy fallback: check Annotations/<pdfFilename>.plist (for files moved into subfolders from v1/v2.0)
        NSString *basePlist = [[_pdfPath lastPathComponent] stringByAppendingPathExtension:@"plist"];
        NSString *legacyPath = [[[self class] annotationsDirectory] stringByAppendingPathComponent:basePlist];
        if (![legacyPath isEqualToString:primaryPath]) {
            data = [NSData dataWithContentsOfFile:legacyPath];
            if (data) {
                loadedPath = legacyPath;
            }
        }
    }

    NSString *defKey = [NSString stringWithFormat:@"lastPage.%@", _annotationKey];
    _lastPageIndex = [[NSUserDefaults standardUserDefaults] integerForKey:defKey];

    if (!data) return;

    id root = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListImmutable
                                                         format:NULL
                                                          error:NULL];
    if (!root) return;

    NSMutableDictionary<NSString *, NSArray *> *rawPages = [NSMutableDictionary dictionary];

    if ([root isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)root;
        if (dict[@"lastPage"] != nil) {
            _lastPageIndex = [dict[@"lastPage"] integerValue];
        }
        if ([dict[@"bookmarks"] isKindOfClass:[NSArray class]]) {
            for (id num in dict[@"bookmarks"]) {
                NSInteger idx = [num integerValue];
                if (idx >= 0) [_bookmarks addIndex:(NSUInteger)idx];
            }
        }
        if ([dict[@"notes"] isKindOfClass:[NSDictionary class]]) {
            NSDictionary *notesMap = dict[@"notes"];
            for (id k in notesMap) {
                NSArray *arr = notesMap[k];
                if ([arr isKindOfClass:[NSArray class]]) {
                    NSMutableArray<TextNote *> *parsedNotes = [NSMutableArray array];
                    for (id nd in arr) {
                        TextNote *note = [TextNote fromDictionary:nd];
                        if (note) [parsedNotes addObject:note];
                    }
                    if (parsedNotes.count > 0) {
                        _notesByPage[[NSString stringWithFormat:@"%ld", (long)[k integerValue]]] = parsedNotes;
                    }
                }
            }
        }

        NSDictionary *pagesSrc = [dict[@"pages"] isKindOfClass:[NSDictionary class]] ? dict[@"pages"] : dict;
        for (id k in pagesSrc) {
            if ([k isEqual:@"v"] || [k isEqual:@"pages"] || [k isEqual:@"notes"] || [k isEqual:@"bookmarks"] || [k isEqual:@"lastPage"]) {
                continue;
            }
            id val = pagesSrc[k];
            if ([val isKindOfClass:[NSArray class]]) {
                rawPages[[NSString stringWithFormat:@"%ld", (long)[k integerValue]]] = val;
            }
        }
    } else if ([root isKindOfClass:[NSArray class]]) {
        // Legacy v1 array migration with proper source-file backup
        NSArray *arr = (NSArray *)root;
        BOOL pureFlat = YES;
        for (id item in arr) {
            if ([item isKindOfClass:[NSArray class]]) {
                pureFlat = NO;
                break;
            }
            if ([item isKindOfClass:[NSDictionary class]] && (item[@"p"] != nil || item[@"page"] != nil)) {
                pureFlat = NO;
                break;
            }
        }
        if (pureFlat) {
            if (arr.count > 0) {
                NSString *bak = [loadedPath stringByAppendingString:@".v2flat.bak"];
                if (![[NSFileManager defaultManager] fileExistsAtPath:bak]) {
                    [[NSFileManager defaultManager] copyItemAtPath:loadedPath toPath:bak error:NULL];
                }
                rawPages[@"0"] = arr;
            }
        } else {
            NSMutableDictionary<NSString *, NSMutableArray *> *grouped = [NSMutableDictionary dictionary];
            for (NSInteger i = 0; i < (NSInteger)arr.count; i++) {
                id item = arr[i];
                if ([item isKindOfClass:[NSArray class]]) {
                    grouped[[NSString stringWithFormat:@"%ld", (long)i]] = [item mutableCopy];
                } else if ([item isKindOfClass:[NSDictionary class]]) {
                    id pObj = item[@"p"] ?: item[@"page"];
                    NSInteger p = pObj ? [pObj integerValue] : 0;
                    NSString *pk = [NSString stringWithFormat:@"%ld", (long)MAX(0, p)];
                    if (!grouped[pk]) grouped[pk] = [NSMutableArray array];
                    [grouped[pk] addObject:item];
                }
            }
            [rawPages addEntriesFromDictionary:grouped];
        }
    }

    for (NSString *pk in rawPages) {
        NSArray *rawList = rawPages[pk];
        NSMutableArray<Stroke *> *strokes = [NSMutableArray arrayWithCapacity:rawList.count];
        for (id d in rawList) {
            Stroke *s = [Stroke fromDictionary:d];
            if (s && s.points.count > 0) {
                [strokes addObject:s];
            }
        }
        if (strokes.count > 0) {
            _strokesByPage[pk] = strokes;
        }
    }
}

#pragma mark - Cloning Helpers

+ (NSArray<Stroke *> *)deepCopyStrokes:(NSArray<Stroke *> *)strokes {
    NSMutableArray<Stroke *> *out = [NSMutableArray arrayWithCapacity:strokes.count];
    for (Stroke *s in strokes) {
        [out addObject:[s copy]];
    }
    return out;
}

+ (NSArray<TextNote *> *)deepCopyNotes:(NSArray<TextNote *> *)notes {
    NSMutableArray<TextNote *> *out = [NSMutableArray arrayWithCapacity:notes.count];
    for (TextNote *n in notes) {
        [out addObject:[n copy]];
    }
    return out;
}

- (void)pushUndoForPage:(NSInteger)pageIndex
          beforeStrokes:(NSArray<Stroke *> *)beforeStrokes
           afterStrokes:(NSArray<Stroke *> *)afterStrokes
            beforeNotes:(NSArray<TextNote *> *)beforeNotes
             afterNotes:(NSArray<TextNote *> *)afterNotes {
    PDFPageEditAction *act = [[PDFPageEditAction alloc] init];
    act.pageIndex = pageIndex;
    act.beforeStrokes = [[self class] deepCopyStrokes:beforeStrokes];
    act.afterStrokes = [[self class] deepCopyStrokes:afterStrokes];
    act.beforeNotes = [[self class] deepCopyNotes:beforeNotes];
    act.afterNotes = [[self class] deepCopyNotes:afterNotes];

    [_undoStack addObject:act];
    if (_undoStack.count > kMaxUndoSteps) {
        [_undoStack removeObjectAtIndex:0];
    }
    [_redoStack removeAllObjects];
}

#pragma mark - Strokes API

- (NSArray<Stroke *> *)strokesForPage:(NSInteger)pageIndex {
    NSString *pk = [NSString stringWithFormat:@"%ld", (long)pageIndex];
    NSArray<Stroke *> *arr = _strokesByPage[pk];
    return arr ? [arr copy] : @[];
}

- (BOOL)hasAnnotationsOnPage:(NSInteger)pageIndex {
    NSString *pk = [NSString stringWithFormat:@"%ld", (long)pageIndex];
    return (_strokesByPage[pk].count > 0 || _notesByPage[pk].count > 0);
}

- (NSUInteger)annotatedPageCount {
    NSMutableSet *keys = [NSMutableSet set];
    for (NSString *k in _strokesByPage) {
        if (_strokesByPage[k].count > 0) [keys addObject:k];
    }
    for (NSString *k in _notesByPage) {
        if (_notesByPage[k].count > 0) [keys addObject:k];
    }
    return keys.count;
}

- (NSIndexSet *)annotatedPages {
    NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
    for (NSString *k in _strokesByPage) {
        if (_strokesByPage[k].count > 0 && [k integerValue] >= 0) {
            [set addIndex:(NSUInteger)[k integerValue]];
        }
    }
    for (NSString *k in _notesByPage) {
        if (_notesByPage[k].count > 0 && [k integerValue] >= 0) {
            [set addIndex:(NSUInteger)[k integerValue]];
        }
    }
    return set;
}

- (void)addStroke:(Stroke *)stroke onPage:(NSInteger)pageIndex {
    if (!stroke || stroke.points.count == 0) return;
    NSString *pk = [NSString stringWithFormat:@"%ld", (long)pageIndex];
    NSArray<Stroke *> *before = [_strokesByPage[pk] copy] ?: @[];
    NSArray<TextNote *> *notes = _notesByPage[pk] ?: @[];

    NSMutableArray<Stroke *> *list = _strokesByPage[pk];
    if (!list) {
        list = [NSMutableArray array];
        _strokesByPage[pk] = list;
    }
    [list addObject:[stroke copy]];
    [self pushUndoForPage:pageIndex beforeStrokes:before afterStrokes:list beforeNotes:notes afterNotes:notes];
    [self markDirty];
}

- (void)replaceStrokes:(NSArray<Stroke *> *)strokes onPage:(NSInteger)pageIndex {
    NSString *pk = [NSString stringWithFormat:@"%ld", (long)pageIndex];
    NSArray<Stroke *> *before = _strokesByPage[pk] ?: @[];
    NSArray<TextNote *> *notes = _notesByPage[pk] ?: @[];

    NSMutableArray<Stroke *> *after = [[[self class] deepCopyStrokes:strokes] mutableCopy];
    if (after.count > 0) {
        _strokesByPage[pk] = after;
    } else {
        [_strokesByPage removeObjectForKey:pk];
    }
    [self pushUndoForPage:pageIndex beforeStrokes:before afterStrokes:after beforeNotes:notes afterNotes:notes];
    [self markDirty];
}

- (void)clearPage:(NSInteger)pageIndex {
    NSString *pk = [NSString stringWithFormat:@"%ld", (long)pageIndex];
    NSArray<Stroke *> *beforeStrokes = _strokesByPage[pk] ?: @[];
    NSArray<TextNote *> *beforeNotes = _notesByPage[pk] ?: @[];
    if (beforeStrokes.count == 0 && beforeNotes.count == 0) return;

    [_strokesByPage removeObjectForKey:pk];
    [_notesByPage removeObjectForKey:pk];
    [self pushUndoForPage:pageIndex beforeStrokes:beforeStrokes afterStrokes:@[] beforeNotes:beforeNotes afterNotes:@[]];
    [self markDirty];
}

#pragma mark - Text Notes API

- (NSArray<TextNote *> *)notesForPage:(NSInteger)pageIndex {
    NSString *pk = [NSString stringWithFormat:@"%ld", (long)pageIndex];
    NSArray<TextNote *> *arr = _notesByPage[pk];
    return arr ? [arr copy] : @[];
}

- (void)saveNote:(TextNote *)note onPage:(NSInteger)pageIndex {
    if (!note) return;
    NSString *pk = [NSString stringWithFormat:@"%ld", (long)pageIndex];
    NSArray<Stroke *> *strokes = _strokesByPage[pk] ?: @[];
    NSArray<TextNote *> *beforeNotes = [[self class] deepCopyNotes:(_notesByPage[pk] ?: @[])];

    NSMutableArray<TextNote *> *list = _notesByPage[pk];
    if (!list) {
        list = [NSMutableArray array];
        _notesByPage[pk] = list;
    }
    NSUInteger found = NSNotFound;
    for (NSUInteger i = 0; i < list.count; i++) {
        if ([list[i].identifier isEqualToString:note.identifier]) {
            found = i;
            break;
        }
    }
    if (found != NSNotFound) {
        list[found] = [note copy];
    } else {
        [list addObject:[note copy]];
    }
    [self pushUndoForPage:pageIndex beforeStrokes:strokes afterStrokes:strokes beforeNotes:beforeNotes afterNotes:list];
    [self markDirty];
}

- (void)deleteNoteWithID:(NSString *)noteID onPage:(NSInteger)pageIndex {
    if (noteID.length == 0) return;
    NSString *pk = [NSString stringWithFormat:@"%ld", (long)pageIndex];
    NSMutableArray<TextNote *> *list = _notesByPage[pk];
    if (!list) return;

    NSArray<Stroke *> *strokes = _strokesByPage[pk] ?: @[];
    NSArray<TextNote *> *beforeNotes = [[self class] deepCopyNotes:list];

    BOOL removed = NO;
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
        if ([list[i].identifier isEqualToString:noteID]) {
            [list removeObjectAtIndex:(NSUInteger)i];
            removed = YES;
        }
    }
    if (!removed) return;
    if (list.count == 0) {
        [_notesByPage removeObjectForKey:pk];
    }
    [self pushUndoForPage:pageIndex beforeStrokes:strokes afterStrokes:strokes beforeNotes:beforeNotes afterNotes:(list ?: @[])];
    [self markDirty];
}

- (void)moveNoteWithID:(NSString *)noteID toNormalizedPosition:(CGPoint)pos onPage:(NSInteger)pageIndex recordUndo:(BOOL)recordUndo {
    NSString *pk = [NSString stringWithFormat:@"%ld", (long)pageIndex];
    NSMutableArray<TextNote *> *list = _notesByPage[pk];
    if (!list) return;

    NSArray<TextNote *> *beforeNotes = recordUndo ? [[self class] deepCopyNotes:list] : nil;
    for (TextNote *n in list) {
        if ([n.identifier isEqualToString:noteID]) {
            n.normalizedPosition = CGPointMake(PDFSafeFloat(pos.x, 0.15f, 0.01f, 0.96f),
                                               PDFSafeFloat(pos.y, 0.15f, 0.01f, 0.96f));
            if (recordUndo) {
                NSArray<Stroke *> *strokes = _strokesByPage[pk] ?: @[];
                [self pushUndoForPage:pageIndex beforeStrokes:strokes afterStrokes:strokes beforeNotes:beforeNotes afterNotes:list];
            }
            [self markDirty];
            break;
        }
    }
}

#pragma mark - Bookmarks & Reading Position

- (BOOL)isPageBookmarked:(NSInteger)pageIndex {
    if (pageIndex < 0) return NO;
    return [_bookmarks containsIndex:(NSUInteger)pageIndex];
}

- (BOOL)toggleBookmarkForPage:(NSInteger)pageIndex {
    if (pageIndex < 0) return NO;
    BOOL nowBookmarked = NO;
    if ([_bookmarks containsIndex:(NSUInteger)pageIndex]) {
        [_bookmarks removeIndex:(NSUInteger)pageIndex];
        nowBookmarked = NO;
    } else {
        [_bookmarks addIndex:(NSUInteger)pageIndex];
        nowBookmarked = YES;
    }
    [self markDirty];
    return nowBookmarked;
}

- (NSIndexSet *)bookmarkedPages {
    return [_bookmarks copy];
}

- (void)setLastPageIndex:(NSInteger)lastPageIndex {
    if (lastPageIndex < 0) lastPageIndex = 0;
    if (_lastPageIndex == lastPageIndex) return;
    _lastPageIndex = lastPageIndex;
    NSString *defKey = [NSString stringWithFormat:@"lastPage.%@", _annotationKey];
    [[NSUserDefaults standardUserDefaults] setInteger:lastPageIndex forKey:defKey];
    if ([self annotatedPageCount] > 0 || _bookmarks.count > 0) {
        [self markDirty];
    }
}

#pragma mark - Undo / Redo

- (BOOL)canUndo {
    return _undoStack.count > 0;
}

- (BOOL)canRedo {
    return _redoStack.count > 0;
}

- (void)applyStateForPage:(NSInteger)pageIndex strokes:(NSArray<Stroke *> *)strokes notes:(NSArray<TextNote *> *)notes {
    NSString *pk = [NSString stringWithFormat:@"%ld", (long)pageIndex];
    if (strokes.count > 0) {
        _strokesByPage[pk] = [[[self class] deepCopyStrokes:strokes] mutableCopy];
    } else {
        [_strokesByPage removeObjectForKey:pk];
    }
    if (notes.count > 0) {
        _notesByPage[pk] = [[[self class] deepCopyNotes:notes] mutableCopy];
    } else {
        [_notesByPage removeObjectForKey:pk];
    }
    [self markDirty];
}

- (NSInteger)undoReturningPage {
    PDFPageEditAction *act = [_undoStack lastObject];
    if (!act) return NSNotFound;
    [_undoStack removeLastObject];
    [_redoStack addObject:act];
    [self applyStateForPage:act.pageIndex strokes:act.beforeStrokes notes:act.beforeNotes];
    return act.pageIndex;
}

- (NSInteger)redoReturningPage {
    PDFPageEditAction *act = [_redoStack lastObject];
    if (!act) return NSNotFound;
    [_redoStack removeLastObject];
    [_undoStack addObject:act];
    [self applyStateForPage:act.pageIndex strokes:act.afterStrokes notes:act.afterNotes];
    return act.pageIndex;
}

#pragma mark - Debounced & Atomic Persistence

- (void)markDirty {
    _dirty = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushSynchronously) object:nil];
    [self performSelector:@selector(flushSynchronously) withObject:nil afterDelay:0.45];
}

- (void)flushSynchronously {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushSynchronously) object:nil];
    if (!_dirty) return;
    [self writeToDiskNow];
}

- (void)writeToDiskNow {
    _dirty = NO;

    NSMutableDictionary *pagesOut = [NSMutableDictionary dictionary];
    for (NSString *pk in _strokesByPage) {
        NSArray<Stroke *> *strokes = _strokesByPage[pk];
        if (strokes.count == 0) continue;
        NSMutableArray *serialized = [NSMutableArray arrayWithCapacity:strokes.count];
        for (Stroke *s in strokes) {
            NSDictionary *d = [s toDictionary];
            if ([d[@"pts"] count] > 0) {
                [serialized addObject:d];
            }
        }
        if (serialized.count > 0) {
            pagesOut[pk] = serialized;
        }
    }

    NSMutableDictionary *notesOut = [NSMutableDictionary dictionary];
    for (NSString *pk in _notesByPage) {
        NSArray<TextNote *> *notes = _notesByPage[pk];
        if (notes.count == 0) continue;
        NSMutableArray *serialized = [NSMutableArray arrayWithCapacity:notes.count];
        for (TextNote *n in notes) {
            [serialized addObject:[n toDictionary]];
        }
        if (serialized.count > 0) {
            notesOut[pk] = serialized;
        }
    }

    NSMutableArray *bmOut = [NSMutableArray array];
    [_bookmarks enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [bmOut addObject:@(idx)];
    }];

    NSString *path = [self filePath];
    if (pagesOut.count == 0 && notesOut.count == 0 && bmOut.count == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        return;
    }

    NSMutableDictionary *root = [NSMutableDictionary dictionary];
    root[@"v"] = @2;
    root[@"pages"] = pagesOut;
    if (notesOut.count > 0) {
        root[@"notes"] = notesOut;
    }
    if (bmOut.count > 0) {
        root[@"bookmarks"] = bmOut;
    }
    if (_lastPageIndex > 0) {
        root[@"lastPage"] = @(_lastPageIndex);
    }

    NSError *err = nil;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:root
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:&err];
    if (plistData) {
        [plistData writeToFile:path options:NSDataWritingAtomic error:NULL];
    }
}

@end

#pragma mark - PDFWeakTimerTarget

@implementation PDFWeakTimerTarget {
    __weak id _target;
    SEL _selector;
}

+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti
                                     target:(id)target
                                   selector:(SEL)selector
                                    repeats:(BOOL)repeats {
    PDFWeakTimerTarget *proxy = [[PDFWeakTimerTarget alloc] init];
    proxy->_target = target;
    proxy->_selector = selector;
    return [NSTimer scheduledTimerWithTimeInterval:ti
                                            target:proxy
                                          selector:@selector(timerFired:)
                                          userInfo:nil
                                           repeats:repeats];
}

- (void)timerFired:(NSTimer *)timer {
    id strongTarget = _target;
    if (!strongTarget) {
        [timer invalidate];
        return;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [strongTarget performSelector:_selector withObject:timer];
#pragma clang diagnostic pop
}

@end
