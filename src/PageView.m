#import "PageView.h"
#import <math.h>

static CGFloat gMainScreenScale = 2.0f;
static const NSUInteger kLiveSegmentPoints = 32;
static const NSUInteger kInkBatchLimit = 8;
static const NSTimeInterval kInkBatchDelay = 0.18;

// Keep page coordinates inside a tightly sized layer (including its nonzero bounds origin).
static void PDFSetInkBounds(CALayer *layer, CGRect bounds) {
    layer.bounds = bounds;
    layer.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
}

static CGFloat PDFClamp(CGFloat v, CGFloat lo, CGFloat hi) {
    if (!isfinite(v)) return lo;
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

static CGFloat PDFPointToSegmentDistSq(CGPoint p, CGPoint a, CGPoint b) {
    CGFloat dx = b.x - a.x;
    CGFloat dy = b.y - a.y;
    CGFloat lenSq = dx * dx + dy * dy;
    CGFloat t = 0.0f;
    if (lenSq > 1e-6f) {
        t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq;
        if (t < 0.0f) t = 0.0f;
        else if (t > 1.0f) t = 1.0f;
    }
    CGFloat cx = a.x + t * dx - p.x;
    CGFloat cy = a.y + t * dy - p.y;
    return cx * cx + cy * cy;
}

static BOOL PDFCCW(CGPoint a, CGPoint b, CGPoint c) {
    return (c.y - a.y) * (b.x - a.x) > (b.y - a.y) * (c.x - a.x);
}

static BOOL PDFSegmentsIntersect(CGPoint a, CGPoint b, CGPoint c, CGPoint d) {
    return (PDFCCW(a, c, d) != PDFCCW(b, c, d)) && (PDFCCW(a, b, c) != PDFCCW(a, b, d));
}

static CGFloat PDFSegmentToSegmentDist(CGPoint a, CGPoint b, CGPoint c, CGPoint d) {
    if (PDFSegmentsIntersect(a, b, c, d)) return 0.0f;
    CGFloat d1 = PDFPointToSegmentDistSq(a, c, d);
    CGFloat d2 = PDFPointToSegmentDistSq(b, c, d);
    CGFloat d3 = PDFPointToSegmentDistSq(c, a, b);
    CGFloat d4 = PDFPointToSegmentDistSq(d, a, b);
    CGFloat minSq = MIN(MIN(d1, d2), MIN(d3, d4));
    return sqrtf((float)minSq);
}

// Pure C/CoreGraphics helper so `[PDFDoc renderQueue]` NEVER retains `PageView` (`UIView`) on a background thread!
static UIImage *PDFRenderInkBitmap(CGSize size,
                                   CGFloat scale,
                                   CGRect trim,
                                   PDFReadingTheme theme,
                                   UIImage *base,
                                   NSArray<Stroke *> *strokes,
                                   PDFCancelToken *token) {
    if (size.width < 2.0f || size.height < 2.0f || strokes.count == 0) {
        return nil;
    }
    @autoreleasepool {
        if (token && token.isCancelled) return nil;

        CGFloat safeTW = (trim.size.width > 0.005f) ? trim.size.width : 1.0f;
        CGFloat safeTH = (trim.size.height > 0.005f) ? trim.size.height : 1.0f;

        UIGraphicsBeginImageContextWithOptions(size, NO, scale);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        if (!ctx) {
            UIGraphicsEndImageContext();
            return nil;
        }

        [base drawInRect:(CGRect){CGPointZero, size}];
        for (Stroke *s in strokes) {
            if (token && token.isCancelled) {
                UIGraphicsEndImageContext();
                return nil;
            }
            if (s.points.count == 0) continue;

            CGContextSaveGState(ctx);
            UIBezierPath *path = [s pathWithPointMap:^CGPoint(CGPoint np) {
                return CGPointMake(((np.x - trim.origin.x) / safeTW) * size.width,
                                   ((np.y - trim.origin.y) / safeTH) * size.height);
            }];
            path.lineWidth = MAX(0.75f, (size.width / safeTW) * s.widthFraction);
            CGContextSetAlpha(ctx, (theme == PDFReadingThemeNight && s.kind == StrokeKindMarker) ? 0.44f : [s alpha]);
            [s.color setStroke];
            [path stroke];
            CGContextRestoreGState(ctx);
        }

        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return img;
    }
}

#pragma mark - Draggable Note Card View

@interface PDFNoteOverlay : UIView
@end

@implementation PDFNoteOverlay
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@interface PDFNoteBadgeView : UIView
@property (nonatomic, strong) TextNote *note;
@property (nonatomic, strong) UILabel *label;
@end

@implementation PDFNoteBadgeView

- (instancetype)initWithNote:(TextNote *)note {
    self = [super initWithFrame:CGRectMake(0, 0, 140, 44)];
    if (self) {
        _note = note;
        self.layer.cornerRadius = 6.0f;
        self.layer.borderWidth = 1.0f;
        self.layer.borderColor = [UIColor colorWithWhite:0.0f alpha:0.22f].CGColor;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.18f;
        self.layer.shadowOffset = CGSizeMake(0.0f, 2.0f);
        self.layer.shadowRadius = 3.0f;

        _label = [[UILabel alloc] initWithFrame:CGRectInset(self.bounds, 7.0f, 5.0f)];
        _label.numberOfLines = 4;
        _label.font = [UIFont systemFontOfSize:12.0f];
        _label.textColor = [UIColor colorWithWhite:0.10f alpha:1.0f];
        [self addSubview:_label];

        [self updateFromNote:note maxWidth:175.0f];
    }
    return self;
}

- (void)updateFromNote:(TextNote *)note maxWidth:(CGFloat)maxWidth {
    _note = note;
    self.backgroundColor = [(note.color ?: [UIColor colorWithRed:0.98f green:0.84f blue:0.25f alpha:1.0f]) colorWithAlphaComponent:0.94f];
    NSString *display = note.text.length > 0 ? note.text : @"Note";
    _label.text = display;
    CGFloat wLimit = MAX(90.0f, maxWidth - 14.0f);
    CGSize fit = [_label sizeThatFits:CGSizeMake(wLimit, 84.0f)];
    CGFloat w = MAX(68.0f, MIN(maxWidth, ceilf((float)fit.width) + 14.0f));
    CGFloat h = MAX(28.0f, MIN(96.0f, ceilf((float)fit.height) + 10.0f));
    self.bounds = CGRectMake(0.0f, 0.0f, w, h);
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:6.0f].CGPath;
    _label.frame = CGRectInset(self.bounds, 7.0f, 5.0f);
}

@end

#pragma mark - PageView Implementation

@implementation PageView {
    PDFDoc *_doc;
    AnnotationStore *_store;

    UIImageView *_imageView;
    UIImageView *_inkImageView;
    UIView *_notesContainer;
    CALayer *_liveContainer;
    CAShapeLayer *_liveLayer;
    CAShapeLayer *_eraserRingLayer;
    UILabel *_bannerLabel;

    NSMutableArray<CALayer *> *_pendingInkLayers;
    NSUInteger _bakedStrokeCount; // NSNotFound: the displayed bitmap is not a usable prefix.
    CGFloat _inkZoomScale;
    NSMutableArray<Stroke *> *_strokes;
    NSMutableArray<TextNote *> *_notes;
    NSMutableArray<PDFNoteBadgeView *> *_noteViews;

    PDFCancelToken *_pdfRenderToken;
    CGFloat _requestedPixelWidth;
    PDFReadingTheme _requestedTheme;
    CGRect _requestedTrim;
    PDFCancelToken *_inkRenderToken;
    NSTimer *_inkBatchTimer;
    CGFloat _renderedPixelWidth;
    PDFReadingTheme _renderedTheme;
    CGRect _renderedTrim;
    CGSize _inkTargetSize;
    CGFloat _inkTargetScale;

    // Active drawing / erasing touch state
    UITouch *_activeTouch;
    NSTimeInterval _touchStartTime;
    CGPoint _touchStartViewPt;
    CGPoint _lastTouchViewPt;
    CGFloat _maxMoveDistance;

    Stroke *_currentStroke;
    CGMutablePathRef _liveCGPath;
    CGPoint _lastSmoothedMidPt;
    CGPoint _prevLiveViewPt;
    NSUInteger _livePointCount;
    NSUInteger _segmentPointCount;
    CGRect _frozenInkBounds;
    BOOL _snappedToStraightLine;
    NSTimer *_lineSnapTimer;
    CFTimeInterval _snapDeadline;

    // Staged eraser indices (only committed on touchesEnded so 2-finger scroll/pinch NEVER erases!)
    NSMutableIndexSet *_stagedErasedIndices;
    BOOL _eraserMovedEnough;
}

+ (void)initialize {
    if (self == [PageView class]) {
        if ([NSThread isMainThread]) {
            gMainScreenScale = [UIScreen mainScreen].scale;
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                gMainScreenScale = [UIScreen mainScreen].scale;
            });
        }
        if (gMainScreenScale < 1.0f) gMainScreenScale = 2.0f;
    }
}

- (instancetype)initWithDoc:(PDFDoc *)doc
                      store:(AnnotationStore *)store
                      index:(NSInteger)index
                       trim:(CGRect)trim
                      theme:(PDFReadingTheme)theme {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _doc = doc;
        _store = store;
        _pageIndex = index;
        _trim = (trim.size.width > 0.005f && trim.size.height > 0.005f) ? trim : CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
        _theme = theme;
        _tool = ReaderToolScroll;
        _drawColor = [UIColor colorWithRed:0.08f green:0.08f blue:0.10f alpha:1.0f];
        _penWidthFraction = 0.004f;
        _markerWidthFraction = 0.03f;
        _snapStraightLines = YES;

        _strokes = [NSMutableArray array];
        _notes = [NSMutableArray array];
        _noteViews = [NSMutableArray array];
        _pendingInkLayers = [NSMutableArray array];
        _inkZoomScale = 1.0f;
        _stagedErasedIndices = [NSMutableIndexSet indexSet];

        self.clipsToBounds = YES;
        self.multipleTouchEnabled = YES;
        self.exclusiveTouch = NO;
        [self updateBackdropForTheme];

        // Subtle card shadow on dark reader canvas
        self.layer.borderWidth = 0.5f;
        self.layer.borderColor = [UIColor colorWithWhite:0.0f alpha:0.25f].CGColor;

        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleToFill;
        _imageView.userInteractionEnabled = NO;
        [self addSubview:_imageView];

        _inkImageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _inkImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _inkImageView.contentMode = UIViewContentModeScaleToFill;
        _inkImageView.userInteractionEnabled = NO;
        [self addSubview:_inkImageView];
        [self updateInkBlendMode];

        _eraserRingLayer = [CAShapeLayer layer];
        _eraserRingLayer.fillColor = [UIColor colorWithWhite:1.0f alpha:0.25f].CGColor;
        _eraserRingLayer.strokeColor = [UIColor colorWithRed:0.92f green:0.28f blue:0.28f alpha:0.88f].CGColor;
        _eraserRingLayer.lineWidth = 1.5f;
        _eraserRingLayer.contentsScale = gMainScreenScale;
        _eraserRingLayer.hidden = YES;
        [self.layer addSublayer:_eraserRingLayer];

        _notesContainer = [[PDFNoteOverlay alloc] initWithFrame:self.bounds];
        _notesContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _notesContainer.backgroundColor = [UIColor clearColor];
        [self addSubview:_notesContainer];

        [self reloadAnnotationsFromStore];
    }
    return self;
}

- (void)dealloc {
    [_inkBatchTimer invalidate];
    [_pdfRenderToken cancel];
    [_inkRenderToken cancel];
    [_lineSnapTimer invalidate];
    if (_liveCGPath) {
        CGPathRelease(_liveCGPath);
        _liveCGPath = NULL;
    }
}

- (void)updateBackdropForTheme {
    if (_theme == PDFReadingThemeSepia) {
        self.backgroundColor = [UIColor colorWithRed:0.965f green:0.925f blue:0.840f alpha:1.0f];
    } else if (_theme == PDFReadingThemeNight) {
        self.backgroundColor = [UIColor colorWithRed:0.11f green:0.11f blue:0.13f alpha:1.0f];
    } else {
        self.backgroundColor = [UIColor whiteColor];
    }
}

- (void)updateInkBlendMode {
    // On Paper & Sepia, Multiply blend mode on the ink layer keeps black PDF text crisp underneath yellow/colored Markers!
    if (_theme == PDFReadingThemeNight) {
        _inkImageView.layer.compositingFilter = nil;
    } else {
        _inkImageView.layer.compositingFilter = @"multiplyBlendMode";
    }
}

- (void)setTheme:(PDFReadingTheme)theme {
    if (_theme == theme) return;
    _theme = theme;
    [self updateBackdropForTheme];
    [self updateInkBlendMode];
    [self invalidateInkBitmap];
}

- (void)setTrim:(CGRect)trim {
    CGRect safe = (trim.size.width > 0.005f && trim.size.height > 0.005f) ? trim : CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
    if (CGRectEqualToRect(_trim, safe)) return;
    _trim = safe;
    [self invalidateInkBitmap];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if ((_inkImageView.image || _inkRenderToken || _pendingInkLayers.count) &&
        !CGSizeEqualToSize(self.bounds.size, _inkTargetSize)) {
        [self scheduleInkRender];
    }
    [self layoutNoteBadges];
}

#pragma mark - Safe Coordinate Conversions

- (CGRect)safeTrim {
    if (_trim.size.width > 0.005f && _trim.size.height > 0.005f &&
        isfinite(_trim.origin.x) && isfinite(_trim.origin.y)) {
        return _trim;
    }
    return CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
}

- (CGPoint)normalisedPointForViewPoint:(CGPoint)pt {
    CGSize sz = self.bounds.size;
    if (sz.width < 2.0f || sz.height < 2.0f) return CGPointMake(0.5f, 0.5f);
    CGRect t = [self safeTrim];
    CGFloat x = t.origin.x + (pt.x / sz.width) * t.size.width;
    CGFloat y = t.origin.y + (pt.y / sz.height) * t.size.height;
    return CGPointMake(PDFClamp(x, -0.25f, 1.25f), PDFClamp(y, -0.25f, 1.25f));
}

- (CGPoint)viewPointForNormalisedPoint:(CGPoint)np inSize:(CGSize)size {
    CGRect t = [self safeTrim];
    CGFloat x = ((np.x - t.origin.x) / t.size.width) * size.width;
    CGFloat y = ((np.y - t.origin.y) / t.size.height) * size.height;
    return CGPointMake(x, y);
}

- (CGFloat)viewWidthForFraction:(CGFloat)frac inSize:(CGSize)size {
    CGRect t = [self safeTrim];
    return MAX(0.75f, (size.width / t.size.width) * frac);
}

- (CGFloat)inkBitmapScaleForZoom:(CGFloat)zoomScale {
    CGSize sz = self.bounds.size;
    CGFloat maxSide = MAX(sz.width, sz.height);
    if (maxSide < 1.0f) return gMainScreenScale;
    CGFloat desired = gMainScreenScale * MAX(1.0f, MIN(zoomScale, 2.2f));
    // Cap ink buffer max side to 2200px to keep RGBA buffer <= ~18MB on iPad 3
    if (maxSide * desired > 2200.0f) {
        desired = 2200.0f / maxSide;
    }
    return desired;
}

#pragma mark - Store Sync & Note Badges

- (void)reloadAnnotationsFromStore {
    [_stagedErasedIndices removeAllIndexes];
    _strokes = [[_store strokesForPage:_pageIndex] mutableCopy] ?: [NSMutableArray array];
    _notes = [[_store notesForPage:_pageIndex] mutableCopy] ?: [NSMutableArray array];
    [self rebuildNoteBadges];

    [self invalidateInkBitmap];
}

- (void)rebuildNoteBadges {
    for (PDFNoteBadgeView *v in _noteViews) {
        [v removeFromSuperview];
    }
    [_noteViews removeAllObjects];

    for (TextNote *note in _notes) {
        PDFNoteBadgeView *badge = [[PDFNoteBadgeView alloc] initWithNote:note];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(noteBadgeTapped:)];
        [badge addGestureRecognizer:tap];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(noteBadgePanned:)];
        [badge addGestureRecognizer:pan];
        [_notesContainer addSubview:badge];
        [_noteViews addObject:badge];
    }
    [self layoutNoteBadges];
}

- (void)layoutNoteBadges {
    CGSize sz = self.bounds.size;
    if (sz.width < 10.0f || sz.height < 10.0f) return;
    CGFloat maxCardW = MIN(185.0f, sz.width * 0.44f);
    for (PDFNoteBadgeView *badge in _noteViews) {
        [badge updateFromNote:badge.note maxWidth:maxCardW];
        CGPoint anchor = [self viewPointForNormalisedPoint:badge.note.normalizedPosition inSize:sz];
        CGFloat x = PDFClamp(anchor.x, 4.0f, MAX(4.0f, sz.width - badge.bounds.size.width - 4.0f));
        CGFloat y = PDFClamp(anchor.y, 4.0f, MAX(4.0f, sz.height - badge.bounds.size.height - 4.0f));
        badge.frame = CGRectMake(x, y, badge.bounds.size.width, badge.bounds.size.height);
    }
}

- (void)noteBadgeTapped:(UITapGestureRecognizer *)gr {
    PDFNoteBadgeView *badge = (PDFNoteBadgeView *)gr.view;
    if ([badge isKindOfClass:[PDFNoteBadgeView class]] && badge.note) {
        [self.delegate pageViewDidInteract:self];
        [self.delegate pageView:self didTapEditNote:badge.note];
    }
}

- (void)noteBadgePanned:(UIPanGestureRecognizer *)gr {
    PDFNoteBadgeView *badge = (PDFNoteBadgeView *)gr.view;
    if (![badge isKindOfClass:[PDFNoteBadgeView class]] || !badge.note) return;

    CGPoint delta = [gr translationInView:self];
    [gr setTranslation:CGPointZero inView:self];

    CGSize sz = self.bounds.size;
    CGRect f = badge.frame;
    f.origin.x = PDFClamp(f.origin.x + delta.x, 4.0f, MAX(4.0f, sz.width - f.size.width - 4.0f));
    f.origin.y = PDFClamp(f.origin.y + delta.y, 4.0f, MAX(4.0f, sz.height - f.size.height - 4.0f));
    badge.frame = f;

    if (gr.state == UIGestureRecognizerStateEnded || gr.state == UIGestureRecognizerStateCancelled) {
        CGPoint norm = [self normalisedPointForViewPoint:f.origin];
        [_store moveNoteWithID:badge.note.identifier toNormalizedPosition:norm onPage:_pageIndex recordUndo:YES];
        [self.delegate pageViewDidChangeAnnotations:self];
    }
}

#pragma mark - Async Rendering & Memory Release

- (BOOL)hasLoadedBitmap {
    return (_imageView.image != nil);
}

- (void)renderContentWithZoomScale:(CGFloat)zoomScale {
    if (CGRectIsEmpty(self.bounds) || self.bounds.size.width < 8.0f) return;

    CGFloat clampedZoom = MAX(1.0f, MIN(zoomScale, 3.0f));
    CGFloat desiredPW = MIN(2560.0f, floorf((float)(self.bounds.size.width * gMainScreenScale * clampedZoom)));
    CGRect curTrim = [self safeTrim];
    PDFReadingTheme curTheme = _theme;

    BOOL needsPDF = (!_imageView.image) ||
                    (_renderedTheme != curTheme) ||
                    (!CGRectEqualToRect(_renderedTrim, curTrim)) ||
                    (fabs((double)(desiredPW - _renderedPixelWidth)) > 110.0);

    if (needsPDF && !_pdfRenderToken) {
        PDFCancelToken *token = [[PDFCancelToken alloc] init];
        _pdfRenderToken = token;
        _requestedPixelWidth = desiredPW;
        _requestedTheme = curTheme;
        _requestedTrim = curTrim;
        PDFDoc *doc = _doc;
        NSInteger idx = _pageIndex;

        __weak typeof(self) weakSelf = self;
        dispatch_async([PDFDoc renderQueue], ^{
            if (token.isCancelled) return;
            UIImage *img = [doc renderPage:idx region:curTrim pixelWidth:desiredPW theme:curTheme];
            if (token.isCancelled) return;

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(self) sSelf = weakSelf;
                if (!sSelf || sSelf->_pdfRenderToken != token || token.isCancelled) return;
                sSelf->_pdfRenderToken = nil;
                if (img) {
                    sSelf->_imageView.image = img;
                    sSelf->_renderedPixelWidth = desiredPW;
                    sSelf->_renderedTheme = curTheme;
                    sSelf->_renderedTrim = curTrim;
                }
                // Check if size/theme changed while rendering
                CGFloat nowPW = MIN(2560.0f, floorf((float)(sSelf.bounds.size.width * gMainScreenScale * clampedZoom)));
                if (sSelf->_theme != curTheme ||
                    !CGRectEqualToRect([sSelf safeTrim], curTrim) ||
                    fabs((double)(nowPW - desiredPW)) > 140.0) {
                    [sSelf renderContentWithZoomScale:clampedZoom];
                }
            });
        });
    } else if (needsPDF && _pdfRenderToken &&
               (_requestedTheme != curTheme ||
                !CGRectEqualToRect(_requestedTrim, curTrim) ||
                fabs((double)(desiredPW - _requestedPixelWidth)) > 110.0)) {
        // Cancel stale in-flight render and schedule fresh one
        [_pdfRenderToken cancel];
        _pdfRenderToken = nil;
        [self renderContentWithZoomScale:clampedZoom];
        return;
    }

    _inkZoomScale = clampedZoom;
    [self scheduleInkRender];
}

- (void)removePendingInkLayers:(NSUInteger)count {
    for (NSUInteger i = 0; i < count; i++) {
        [_pendingInkLayers[i] removeFromSuperlayer];
    }
    [_pendingInkLayers removeObjectsInRange:NSMakeRange(0, count)];
}

- (void)invalidateInkBitmap {
    [_inkRenderToken cancel];
    _bakedStrokeCount = NSNotFound;
    [self scheduleInkRender];
}

- (void)batchFinishedInk {
    // Finished overlays are already visible. Flatten a burst only once, after a
    // pause or eight pending strokes; an in-flight render already drains its tail.
    if (!_pendingInkLayers.count || _inkRenderToken) return;
    if (_pendingInkLayers.count >= kInkBatchLimit) {
        [self scheduleInkRender];
    } else if (_inkBatchTimer) {
        _inkBatchTimer.fireDate = [NSDate dateWithTimeIntervalSinceNow:kInkBatchDelay];
    } else {
        _inkBatchTimer = [PDFWeakTimerTarget scheduledTimerWithTimeInterval:kInkBatchDelay target:self
                                                                   selector:@selector(inkBatchTimerFired:) repeats:NO];
    }
}

- (void)inkBatchTimerFired:(NSTimer *)timer {
    if (timer != _inkBatchTimer) return;
    _inkBatchTimer = nil;
    if (!_currentStroke) [self scheduleInkRender];
}

- (void)scheduleInkRender {
    [_inkBatchTimer invalidate];
    _inkBatchTimer = nil;
    CGSize sz = self.bounds.size;
    CGFloat scale = [self inkBitmapScaleForZoom:_inkZoomScale];
    if (!CGSizeEqualToSize(sz, _inkTargetSize) || scale != _inkTargetScale) {
        [_inkRenderToken cancel];
        _bakedStrokeCount = NSNotFound;
        _inkTargetSize = sz;
        _inkTargetScale = scale;
    }

    NSUInteger count = _strokes.count;
    if (count == _stagedErasedIndices.count || sz.width < 2.0f || sz.height < 2.0f) {
        [_inkRenderToken cancel];
        _inkImageView.image = nil;
        [self removePendingInkLayers:_pendingInkLayers.count];
        _bakedStrokeCount = count == 0 ? 0 : NSNotFound;
        return;
    }
    if (_inkRenderToken || _bakedStrokeCount == count) return;

    // The base is valid only for append-only edits. Finished strokes are never mutated.
    UIImage *base = nil;
    NSArray<Stroke *> *snap;
    if (_bakedStrokeCount == NSNotFound) {
        NSMutableArray *visible = [_strokes mutableCopy];
        [visible removeObjectsAtIndexes:_stagedErasedIndices];
        snap = visible;
    } else {
        base = _inkImageView.image;
        snap = [_strokes subarrayWithRange:NSMakeRange(_bakedStrokeCount, count - _bakedStrokeCount)];
    }
    NSUInteger coveredLayers = _pendingInkLayers.count;
    CGRect trim = [self safeTrim];
    PDFReadingTheme theme = _theme;
    PDFCancelToken *token = [[PDFCancelToken alloc] init];
    _inkRenderToken = token;

    __weak typeof(self) weakSelf = self;
    dispatch_async([PDFDoc renderQueue], ^{
        UIImage *img = PDFRenderInkBitmap(sz, scale, trim, theme, base, snap, token);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(self) page = weakSelf;
            if (!page || page->_inkRenderToken != token) return;
            page->_inkRenderToken = nil;
            if (!token.isCancelled && CGSizeEqualToSize(sz, page.bounds.size)) {
                // Allocation failure: keep the visible ink and retry on the next request.
                if (!img) return;
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                page->_inkImageView.image = img;
                [page removePendingInkLayers:coveredLayers];
                page->_bakedStrokeCount = count;
                [CATransaction commit];
            }
            // Coalesce edits made during this job, including cancellation/reload.
            [page scheduleInkRender];
        });
    });
}

- (void)releaseContent {
    [_stagedErasedIndices removeAllIndexes];
    [self cancelActiveTouchIfNeeded];
    [_inkBatchTimer invalidate];
    _inkBatchTimer = nil;

    [_pdfRenderToken cancel];
    _pdfRenderToken = nil;
    _imageView.image = nil;
    _renderedPixelWidth = 0.0f;

    [_inkRenderToken cancel];
    _inkRenderToken = nil;
    _inkImageView.image = nil;
    [self removePendingInkLayers:_pendingInkLayers.count];
    _bakedStrokeCount = NSNotFound;
}

#pragma mark - Search Match Banner Pulse

- (void)pulseHighlightBanner:(NSString *)bannerText {
    if (!_bannerLabel) {
        _bannerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _bannerLabel.backgroundColor = [UIColor colorWithRed:0.96f green:0.76f blue:0.18f alpha:0.95f];
        _bannerLabel.textColor = [UIColor colorWithWhite:0.10f alpha:1.0f];
        _bannerLabel.font = [UIFont boldSystemFontOfSize:13.0f];
        _bannerLabel.textAlignment = NSTextAlignmentCenter;
        _bannerLabel.layer.cornerRadius = 12.0f;
        _bannerLabel.clipsToBounds = YES;
        _bannerLabel.alpha = 0.0f;
        [self addSubview:_bannerLabel];
    }
    _bannerLabel.text = bannerText.length > 0 ? [NSString stringWithFormat:@"  %@  ", bannerText] : @"  Match on this page  ";
    [_bannerLabel sizeToFit];
    CGFloat w = MIN(self.bounds.size.width - 24.0f, MAX(140.0f, _bannerLabel.bounds.size.width + 16.0f));
    _bannerLabel.frame = CGRectMake((self.bounds.size.width - w) * 0.5f, 12.0f, w, 26.0f);
    _bannerLabel.alpha = 1.0f;

    UIColor *origBorder = [UIColor colorWithWhite:0.0f alpha:0.25f];
    self.layer.borderWidth = 3.0f;
    self.layer.borderColor = [UIColor colorWithRed:0.98f green:0.78f blue:0.18f alpha:1.0f].CGColor;

    [UIView animateWithDuration:0.35 delay:1.4 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _bannerLabel.alpha = 0.0f;
    } completion:^(BOOL finished) {
        self.layer.borderWidth = 0.5f;
        self.layer.borderColor = origBorder.CGColor;
    }];
}

#pragma mark - Touch & Gesture State Machine

- (BOOL)isDrawingOrAnnotatingTool {
    return (_tool == ReaderToolPen || _tool == ReaderToolMarker || _tool == ReaderToolEraser || _tool == ReaderToolNote);
}

- (void)setTool:(ReaderTool)tool {
    if (_tool == tool) return;
    [self cancelActiveTouchIfNeeded];
    _tool = tool;
}

- (CAShapeLayer *)newLiveSegment {
    CAShapeLayer *segment = [CAShapeLayer layer];
    segment.fillColor = NULL;
    segment.lineCap = kCALineCapRound;
    segment.lineJoin = kCALineJoinRound;
    segment.contentsScale = gMainScreenScale;
    segment.strokeColor = [_currentStroke.color colorWithAlphaComponent:1.0f].CGColor;
    segment.lineWidth = [self viewWidthForFraction:_currentStroke.widthFraction inSize:self.bounds.size];
    [_liveContainer addSublayer:segment];
    return segment;
}

- (void)displayLivePath:(CGPathRef)path {
    _liveLayer.path = path;
    CGRect box = CGPathGetBoundingBox(path);
    if (CGRectIsNull(box)) return;
    CGFloat pad = ceil(_liveLayer.lineWidth * 0.5f) + 1.0f;
    box = CGRectIntegral(CGRectInset(box, -pad, -pad));
    PDFSetInkBounds(_liveLayer, box);
    PDFSetInkBounds(_liveContainer, CGRectUnion(_frozenInkBounds, box));
}

- (void)freezeLiveSegment {
    [self displayLivePath:_liveCGPath];
    _frozenInkBounds = _liveContainer.bounds;
    _liveLayer = [self newLiveSegment];
    CGPathRelease(_liveCGPath);
    _liveCGPath = CGPathCreateMutable();
    CGPathMoveToPoint(_liveCGPath, NULL, _lastSmoothedMidPt.x, _lastSmoothedMidPt.y);
    _segmentPointCount = 0;
}

- (void)displayLiveTip {
    // The smoothed prefix ends at a midpoint. Extend only the preview to the real
    // sample; the next sample will replace this line with the correct curve.
    CGMutablePathRef preview = CGPathCreateMutableCopy(_liveCGPath);
    CGPathAddLineToPoint(preview, NULL, _prevLiveViewPt.x, _prevLiveViewPt.y);
    [self displayLivePath:preview];
    CGPathRelease(preview);
}

- (void)clearLiveLayer {
    [_lineSnapTimer invalidate];
    _lineSnapTimer = nil;
    _snappedToStraightLine = NO;
    _livePointCount = 0;

    if (_liveCGPath) {
        CGPathRelease(_liveCGPath);
        _liveCGPath = NULL;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_liveContainer removeFromSuperlayer];
    _liveContainer = nil;
    _liveLayer = nil;
    _eraserRingLayer.hidden = YES;
    [CATransaction commit];
}

- (void)cancelActiveTouchIfNeeded {
    if (!_activeTouch && !_currentStroke && _stagedErasedIndices.count == 0) {
        return;
    }
    _activeTouch = nil;
    _currentStroke = nil;
    [self clearLiveLayer];

    if (_stagedErasedIndices.count > 0) {
        [_stagedErasedIndices removeAllIndexes];
        [self invalidateInkBitmap];
    } else {
        [self batchFinishedInk];
    }
    _eraserMovedEnough = NO;
}

- (void)scheduleStraightLineSnapCheck:(CGPoint)latestPt {
    CGFloat dx = latestPt.x - _touchStartViewPt.x;
    CGFloat dy = latestPt.y - _touchStartViewPt.y;
    if (!_snapStraightLines || !_currentStroke || _snappedToStraightLine ||
        (dx * dx + dy * dy) < (22.0f * 22.0f)) {
        [_lineSnapTimer invalidate];
        _lineSnapTimer = nil;
        return;
    }
    _snapDeadline = CACurrentMediaTime() + 0.42;
    if (!_lineSnapTimer) [self armSnapTimerAfter:0.42];
}

- (void)armSnapTimerAfter:(NSTimeInterval)delay {
    _lineSnapTimer = [PDFWeakTimerTarget scheduledTimerWithTimeInterval:delay target:self
                                                               selector:@selector(lineSnapTimerFired:) repeats:NO];
}

- (void)lineSnapTimerFired:(NSTimer *)timer {
    _lineSnapTimer = nil;
    if (!_currentStroke || !_activeTouch || _snappedToStraightLine || !_snapStraightLines) return;
    CFTimeInterval remaining = _snapDeadline - CACurrentMediaTime();
    if (remaining > 0.0) {
        [self armSnapTimerAfter:remaining];
        return;
    }

    _snappedToStraightLine = YES;
    [self updateSnappedStraightLineToViewPoint:_lastTouchViewPt];
}

- (void)updateSnappedStraightLineToViewPoint:(CGPoint)endPt {
    if (!_currentStroke) return;
    CGPoint startNorm = [_currentStroke.points.firstObject CGPointValue];
    CGPoint endNorm = [self normalisedPointForViewPoint:endPt];
    [_currentStroke.points removeAllObjects];
    [_currentStroke addNormalizedPoint:startNorm];
    [_currentStroke addNormalizedPoint:endNorm];

    UIBezierPath *line = [UIBezierPath bezierPath];
    [line moveToPoint:_touchStartViewPt];
    [line addLineToPoint:endPt];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // A snapped line replaces the entire freehand stroke, not just its last segment.
    if (_liveContainer.sublayers.count > 1) {
        _liveContainer.sublayers = nil;
        [_liveContainer addSublayer:_liveLayer];
    }
    _frozenInkBounds = CGRectNull;
    [self displayLivePath:line.CGPath];
    [CATransaction commit];
}

- (void)updateEraserRingAtPoint:(CGPoint)pt visible:(BOOL)visible {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _eraserRingLayer.hidden = !visible;
    if (visible) {
        CGFloat r = 14.0f;
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(pt.x - r, pt.y - r, r * 2.0f, r * 2.0f)];
        _eraserRingLayer.path = circle.CGPath;
    }
    [CATransaction commit];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.delegate pageViewDidInteract:self];
    if (![self isDrawingOrAnnotatingTool] || CGRectIsEmpty(self.bounds)) {
        [super touchesBegan:touches withEvent:event];
        return;
    }

    NSSet<UITouch *> *allInView = [event touchesForView:self];
    // Multi-touch guard: if user puts 2 fingers down to pan/zoom, cancel uncommitted single-finger action immediately!
    if (allInView.count >= 2) {
        NSTimeInterval elapsed = [NSProcessInfo processInfo].systemUptime - _touchStartTime;
        if (!_activeTouch || (elapsed < 0.16 && _maxMoveDistance < 14.0f) || _tool == ReaderToolEraser || _tool == ReaderToolNote) {
            [self cancelActiveTouchIfNeeded];
            return;
        }
        // Otherwise user is mid-handwriting and rested a palm — ignore the extra touch!
        return;
    }

    if (_activeTouch) return;

    UITouch *t = [touches anyObject];
    if (!t) return;
    CGPoint p = [t locationInView:self];

    _activeTouch = t;
    _touchStartTime = [NSProcessInfo processInfo].systemUptime;
    _touchStartViewPt = p;
    _lastTouchViewPt = p;
    _maxMoveDistance = 0.0f;

    [self.delegate pageViewDidBeginDrawing:self];

    if (_tool == ReaderToolNote) {
        return;
    }

    if (_tool == ReaderToolEraser) {
        [_stagedErasedIndices removeAllIndexes];
        _eraserMovedEnough = NO;
        [self updateEraserRingAtPoint:p visible:YES];
        return;
    }

    // Pen or Marker
    _currentStroke = [[Stroke alloc] init];
    _currentStroke.kind = (_tool == ReaderToolMarker) ? StrokeKindMarker : StrokeKindPen;
    _currentStroke.color = _drawColor ?: [UIColor blackColor];
    _currentStroke.widthFraction = (_tool == ReaderToolMarker) ? _markerWidthFraction : _penWidthFraction;
    [_currentStroke addNormalizedPoint:[self normalisedPointForViewPoint:p]];

    if (_liveCGPath) CGPathRelease(_liveCGPath);
    _liveCGPath = CGPathCreateMutable();
    CGPathMoveToPoint(_liveCGPath, NULL, p.x, p.y);
    CGPathAddLineToPoint(_liveCGPath, NULL, p.x + 0.15f, p.y);
    _prevLiveViewPt = p;
    _lastSmoothedMidPt = p;
    _livePointCount = 1;
    _segmentPointCount = 1;
    _snappedToStraightLine = NO;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _liveContainer = [CALayer layer];
    _frozenInkBounds = CGRectNull;
    // Composite the marker once, so neither overlapping segment caps nor
    // self-intersections make a single stroke darker.
    _liveContainer.allowsGroupOpacity = YES;
    _liveContainer.opacity = (_currentStroke.kind == StrokeKindMarker && _theme == PDFReadingThemeNight)
                           ? 0.44f : _currentStroke.alpha;
    [self.layer insertSublayer:_liveContainer below:_eraserRingLayer];
    _liveLayer = [self newLiveSegment];
    [self displayLivePath:_liveCGPath];
    [CATransaction commit];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_activeTouch || ![touches containsObject:_activeTouch]) return;

    NSSet<UITouch *> *allInView = [event touchesForView:self];
    if (allInView.count >= 2) {
        NSTimeInterval elapsed = [NSProcessInfo processInfo].systemUptime - _touchStartTime;
        if ((elapsed < 0.16 && _maxMoveDistance < 14.0f) || _tool == ReaderToolEraser || _tool == ReaderToolNote) {
            [self cancelActiveTouchIfNeeded];
            return;
        }
    }

    NSArray<UITouch *> *samples = nil;
    if ([event respondsToSelector:@selector(coalescedTouchesForTouch:)]) {
        samples = [event coalescedTouchesForTouch:_activeTouch];
    }
    if (samples.count == 0) {
        samples = @[_activeTouch];
    }

    if (_tool == ReaderToolNote) {
        CGPoint cur = [_activeTouch locationInView:self];
        CGFloat d = hypotf((float)(cur.x - _touchStartViewPt.x), (float)(cur.y - _touchStartViewPt.y));
        if (d > _maxMoveDistance) _maxMoveDistance = d;
        _lastTouchViewPt = cur;
        return;
    }

    if (_tool == ReaderToolEraser) {
        BOOL newlyStaged = NO;
        for (UITouch *st in samples) {
            CGPoint pt = [st locationInView:self];
            CGFloat distFromStart = hypotf((float)(pt.x - _touchStartViewPt.x), (float)(pt.y - _touchStartViewPt.y));
            if (distFromStart > _maxMoveDistance) _maxMoveDistance = distFromStart;

            if (_maxMoveDistance >= 3.5f) {
                if (!_eraserMovedEnough) {
                    _eraserMovedEnough = YES;
                    newlyStaged |= [self stageEraseAlongSegmentFrom:_touchStartViewPt to:pt];
                } else {
                    newlyStaged |= [self stageEraseAlongSegmentFrom:_lastTouchViewPt to:pt];
                }
            }
            _lastTouchViewPt = pt;
        }
        [self updateEraserRingAtPoint:_lastTouchViewPt visible:YES];
        if (newlyStaged) {
            [self invalidateInkBitmap];
        }
        return;
    }

    if (!_currentStroke) return;

    if (_snappedToStraightLine) {
        CGPoint endPt = [_activeTouch locationInView:self];
        _lastTouchViewPt = endPt;
        [self updateSnappedStraightLineToViewPoint:endPt];
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    BOOL addedAny = NO;
    for (UITouch *st in samples) {
        CGPoint p = [st locationInView:self];
        CGFloat distFromStart = hypotf((float)(p.x - _touchStartViewPt.x), (float)(p.y - _touchStartViewPt.y));
        if (distFromStart > _maxMoveDistance) _maxMoveDistance = distFromStart;

        CGFloat stepSq = (p.x - _prevLiveViewPt.x) * (p.x - _prevLiveViewPt.x) +
                         (p.y - _prevLiveViewPt.y) * (p.y - _prevLiveViewPt.y);
        if (stepSq * _inkZoomScale * _inkZoomScale < 0.65f) continue;

        [_currentStroke addNormalizedPoint:[self normalisedPointForViewPoint:p]];
        CGPoint mid = CGPointMake((_prevLiveViewPt.x + p.x) * 0.5f, (_prevLiveViewPt.y + p.y) * 0.5f);
        if (_livePointCount == 1) {
            CGPathRelease(_liveCGPath);
            _liveCGPath = CGPathCreateMutable();
            CGPathMoveToPoint(_liveCGPath, NULL, _touchStartViewPt.x, _touchStartViewPt.y);
            CGPathAddLineToPoint(_liveCGPath, NULL, mid.x, mid.y);
        } else {
            CGPathAddQuadCurveToPoint(_liveCGPath, NULL, _prevLiveViewPt.x, _prevLiveViewPt.y, mid.x, mid.y);
        }
        _prevLiveViewPt = p;
        _lastSmoothedMidPt = mid;
        _livePointCount++;
        _segmentPointCount++;
        _lastTouchViewPt = p;
        if (_segmentPointCount >= kLiveSegmentPoints) [self freezeLiveSegment];
        addedAny = YES;
    }

    if (addedAny) {
        [self displayLiveTip];
        [self scheduleStraightLineSnapCheck:_lastTouchViewPt];
    }
    [CATransaction commit];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_activeTouch || ![touches containsObject:_activeTouch]) return;
    CGPoint endPt = [_activeTouch locationInView:self];
    _activeTouch = nil;

    if (_tool == ReaderToolNote) {
        if (_maxMoveDistance < 12.0f) {
            CGPoint normPt = [self normalisedPointForViewPoint:endPt];
            [self.delegate pageView:self didTapCreateNoteAtNormalizedPoint:normPt];
        }
        [self.delegate pageViewDidInteract:self];
        return;
    }

    if (_tool == ReaderToolEraser) {
        if (!_eraserMovedEnough) {
            // Single-finger intentional tap finished without pinch/pan cancellation -> erase at tap point!
            [self stageEraseAlongSegmentFrom:endPt to:endPt];
        }
        [self clearLiveLayer];
        if (_stagedErasedIndices.count > 0) {
            NSMutableArray<Stroke *> *remaining = [NSMutableArray arrayWithCapacity:_strokes.count];
            for (NSUInteger i = 0; i < _strokes.count; i++) {
                if (![_stagedErasedIndices containsIndex:i]) {
                    [remaining addObject:_strokes[i]];
                }
            }
            [_stagedErasedIndices removeAllIndexes];
            _strokes = remaining;
            [_store replaceStrokes:_strokes onPage:_pageIndex];
            [self invalidateInkBitmap];
            [self.delegate pageViewDidChangeAnnotations:self];
        }
        _eraserMovedEnough = NO;
        [self.delegate pageViewDidInteract:self];
        return;
    }

    if (_currentStroke) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (_snappedToStraightLine) {
            [self updateSnappedStraightLineToViewPoint:endPt];
        } else if (_livePointCount >= 2) {
            [_currentStroke addNormalizedPoint:[self normalisedPointForViewPoint:endPt]];
            CGPathAddQuadCurveToPoint(_liveCGPath, NULL, _prevLiveViewPt.x, _prevLiveViewPt.y, endPt.x, endPt.y);
            [self displayLivePath:_liveCGPath];
        } else if (hypotf(endPt.x - _touchStartViewPt.x, endPt.y - _touchStartViewPt.y) >= 0.4f) {
            // A fast flick may have no intervening touchesMoved callback.
            [_currentStroke addNormalizedPoint:[self normalisedPointForViewPoint:endPt]];
            CGMutablePathRef line = CGPathCreateMutable();
            CGPathMoveToPoint(line, NULL, _touchStartViewPt.x, _touchStartViewPt.y);
            CGPathAddLineToPoint(line, NULL, endPt.x, endPt.y);
            [self displayLivePath:line];
            CGPathRelease(line);
        }
        Stroke *finished = _currentStroke;
        _currentStroke = nil;

        if (finished.points.count > 0) {
            [_inkImageView.layer addSublayer:_liveContainer];
            [_pendingInkLayers addObject:_liveContainer];
            _liveContainer = nil; // The bitmap completion retires this overlay.
            [_strokes addObject:finished];
            [_store addStroke:finished onPage:_pageIndex];
            [self batchFinishedInk];
            [self.delegate pageViewDidChangeAnnotations:self];
        }
        [self clearLiveLayer];
        [CATransaction commit];
    }
    [self.delegate pageViewDidInteract:self];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_activeTouch || ![touches containsObject:_activeTouch]) return;
    [self cancelActiveTouchIfNeeded];
    [self.delegate pageViewDidInteract:self];
}

#pragma mark - Continuous Segment-to-Segment Eraser Hit Testing

- (BOOL)stageEraseAlongSegmentFrom:(CGPoint)segA to:(CGPoint)segB {
    if (_strokes.count == 0) return NO;
    CGSize sz = self.bounds.size;
    if (sz.width < 2.0f || sz.height < 2.0f) return NO;

    CGPoint normA = [self normalisedPointForViewPoint:segA];
    CGPoint normB = [self normalisedPointForViewPoint:segB];
    CGFloat minNX = MIN(normA.x, normB.x) - 0.06f;
    CGFloat maxNX = MAX(normA.x, normB.x) + 0.06f;
    CGFloat minNY = MIN(normA.y, normB.y) - 0.06f;
    CGFloat maxNY = MAX(normA.y, normB.y) + 0.06f;
    CGRect queryNormRect = CGRectMake(minNX, minNY, maxNX - minNX, maxNY - minNY);

    BOOL hitAnyNew = NO;
    for (NSUInteger i = 0; i < _strokes.count; i++) {
        if ([_stagedErasedIndices containsIndex:i]) continue;
        Stroke *s = _strokes[i];
        if (s.points.count == 0) continue;

        CGRect sb = [s normalizedBounds];
        if (!CGRectIsNull(sb) && !CGRectIntersectsRect(sb, queryNormRect)) {
            continue;
        }

        CGFloat sw = [self viewWidthForFraction:s.widthFraction inSize:sz];
        CGFloat threshold = 13.0f + sw * 0.5f;

        CGPoint prev = [self viewPointForNormalisedPoint:[s.points[0] CGPointValue] inSize:sz];
        BOOL hit = (PDFSegmentToSegmentDist(segA, segB, prev, prev) < threshold);
        if (!hit) {
            for (NSUInteger pIdx = 1; pIdx < s.points.count; pIdx++) {
                CGPoint cur = [self viewPointForNormalisedPoint:[s.points[pIdx] CGPointValue] inSize:sz];
                if (PDFSegmentToSegmentDist(segA, segB, prev, cur) < threshold) {
                    hit = YES;
                    break;
                }
                prev = cur;
            }
        }

        if (hit) {
            [_stagedErasedIndices addIndex:i];
            hitAnyNew = YES;
        }
    }
    return hitAnyNew;
}

@end
