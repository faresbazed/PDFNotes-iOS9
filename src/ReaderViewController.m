#import "ReaderViewController.h"
#import "Models.h"
#import "PDFDoc.h"
#import "PDFIcons.h"
#import "PageView.h"
#import "NavigationSheetController.h"
#import "ReaderNavigation.h"
#import <math.h>

static NSString *const kPrefToolKey         = @"reader.tool";
static NSString *const kPrefAutoTrimKey     = @"reader.autoTrim";
static NSString *const kPrefThemeKey        = @"reader.theme";
static NSString *const kPrefSnapLineKey     = @"reader.snapLine";
static NSString *const kPrefPenWidthKey     = @"reader.penWidth";
static NSString *const kPrefMarkerWidthKey  = @"reader.markerWidth";
static NSString *const kPrefPenColorRKey    = @"reader.penR";
static NSString *const kPrefPenColorGKey    = @"reader.penG";
static NSString *const kPrefPenColorBKey    = @"reader.penB";
static NSString *const kPrefMarkerColorRKey = @"reader.markerR";
static NSString *const kPrefMarkerColorGKey = @"reader.markerG";
static NSString *const kPrefMarkerColorBKey = @"reader.markerB";

static UIImage *PDFRainbowTrackImage(CGSize size) {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        UIBezierPath *clip = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height)
                                                        cornerRadius:size.height * 0.5f];
        [clip addClip];
        int steps = 48;
        CGFloat stepW = size.width / (CGFloat)steps;
        for (int i = 0; i < steps; i++) {
            CGFloat hue = (CGFloat)i / (CGFloat)steps;
            [[UIColor colorWithHue:hue saturation:0.90f brightness:0.92f alpha:1.0f] setFill];
            CGContextFillRect(ctx, CGRectMake((CGFloat)i * stepW, 0.0f, stepW + 1.0f, size.height));
        }
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img resizableImageWithCapInsets:UIEdgeInsetsMake(0, 4, 0, 4)];
}

@interface PDFStrokePreviewView : UIView
@property (nonatomic, strong) UIColor *strokeColor;
@property (nonatomic, assign) CGFloat lineWidthPts;
@property (nonatomic, assign) CGFloat strokeAlpha;
@end

@implementation PDFStrokePreviewView

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    UIBezierPath *bg = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:6.0f];
    [[UIColor colorWithWhite:0.96f alpha:1.0f] setFill];
    [bg fill];

    CGContextSaveGState(ctx);
    UIBezierPath *wave = [UIBezierPath bezierPath];
    wave.lineCapStyle = kCGLineCapRound;
    wave.lineWidth = MAX(1.2f, MIN(rect.size.height - 6.0f, _lineWidthPts));
    CGFloat midY = rect.size.height * 0.5f;
    [wave moveToPoint:CGPointMake(14.0f, midY + 3.0f)];
    [wave addCurveToPoint:CGPointMake(rect.size.width - 14.0f, midY - 2.0f)
            controlPoint1:CGPointMake(rect.size.width * 0.35f, midY - 9.0f)
            controlPoint2:CGPointMake(rect.size.width * 0.65f, midY + 9.0f)];
    CGContextSetAlpha(ctx, _strokeAlpha > 0.0f ? _strokeAlpha : 1.0f);
    [(_strokeColor ?: [UIColor blackColor]) setStroke];
    [wave stroke];
    CGContextRestoreGState(ctx);
}

@end

@interface ReaderViewController () <UIScrollViewDelegate, PageViewDelegate, UIGestureRecognizerDelegate, UISearchBarDelegate>
@end

@implementation ReaderViewController {
    NSString *_pdfPath;
    PDFDoc *_doc;
    AnnotationStore *_store;

    // Virtualized page geometry & active views (keeps RAM tiny on 1GB iPad 3!)
    NSMutableArray<NSValue *> *_pageFrames;
    NSMutableDictionary<NSNumber *, PageView *> *_loadedPages;
    CGSize _lastLayoutSize;
    BOOL _pagesReady;
    BOOL _didRestoreInitialPage;
    BOOL _isClosing;

    // Preferences & tool state
    ReaderTool _tool;
    BOOL _autoTrim;
    PDFReadingTheme _theme;
    BOOL _snapLines;
    UIColor *_penColor;
    UIColor *_markerColor;
    CGFloat _penWidthFraction;
    CGFloat _markerWidthFraction;

    // Main scroll hierarchy
    UIScrollView *_scrollView;
    UIView *_contentView;

    // Floating dock & buttons
    UIView *_dockContainer;
    UIScrollView *_dockScroll;
    UIButton *_backBtn;
    UIButton *_gridBtn;
    UIButton *_readBtn;
    UIButton *_penBtn;
    UIButton *_markerBtn;
    UIButton *_eraserBtn;
    UIButton *_noteBtn;
    UIButton *_colorBtn;
    UIView *_colorInnerDisc;
    UIButton *_undoBtn;
    UIButton *_redoBtn;
    UIButton *_trashBtn;
    UIButton *_bookmarkBtn;
    UIButton *_searchBtn;
    UIButton *_optionsBtn;
    UIButton *_shareBtn;

    UIButton *_edgeTab;
    UIButton *_pagePillBtn;
    BOOL _dockHidden;
    NSTimer *_hideTimer;

    // Style popover panel
    UIView *_stylePanel;
    BOOL _panelOpen;
    NSMutableArray<UIButton *> *_swatchButtons;
    UISlider *_hueSlider;
    UISlider *_widthSlider;
    UILabel *_widthTitleLabel;
    PDFStrokePreviewView *_strokePreview;
    UISwitch *_snapSwitch;

    // In-PDF Search bar
    UIView *_searchContainer;
    UISearchBar *_searchBar;
    UILabel *_searchStatusLabel;
    UIButton *_searchPrevBtn;
    UIButton *_searchNextBtn;
    PDFCancelToken *_searchToken;
    NSArray<PDFSearchMatch *> *_searchMatches;
    NSInteger _currentMatchIndex;
    NSMutableArray<NSNumber *> *_jumpHistory;

    // Loading / Error / Export overlay (NEVER blocks Back button!)
    UIView *_loadingOverlay;
    UIActivityIndicatorView *_spinner;
    UILabel *_loadingLabel;
    UIProgressView *_progressBar;
    UIButton *_overlayActionBtn;

    PDFCancelToken *_trimCancelToken;
    PDFCancelToken *_exportCancelToken;
}

- (instancetype)initWithPath:(NSString *)pdfPath {
    self = [super init];
    if (self) {
        _pdfPath = [pdfPath copy];
        _pageFrames = [NSMutableArray array];
        _loadedPages = [NSMutableDictionary dictionary];
        _swatchButtons = [NSMutableArray array];
        _jumpHistory = [NSMutableArray array];
        _currentMatchIndex = -1;
        [self loadUserPreferences];
    }
    return self;
}

- (void)dealloc {
    _isClosing = YES;
    [_hideTimer invalidate];
    [_trimCancelToken cancel];
    [_searchToken cancel];
    [_exportCancelToken cancel];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

#pragma mark - User Preferences

- (void)loadUserPreferences {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:kPrefAutoTrimKey] != nil) {
        _autoTrim = [ud boolForKey:kPrefAutoTrimKey];
    } else {
        _autoTrim = YES;
    }
    if ([ud objectForKey:kPrefSnapLineKey] != nil) {
        _snapLines = [ud boolForKey:kPrefSnapLineKey];
    } else {
        _snapLines = YES;
    }

    NSInteger savedTheme = [ud integerForKey:kPrefThemeKey];
    _theme = (savedTheme >= PDFReadingThemePaper && savedTheme <= PDFReadingThemeNight) ? (PDFReadingTheme)savedTheme : PDFReadingThemePaper;

    NSInteger savedTool = [ud integerForKey:kPrefToolKey];
    _tool = (savedTool >= ReaderToolScroll && savedTool <= ReaderToolNote) ? (ReaderTool)savedTool : ReaderToolScroll;

    float pw = [ud floatForKey:kPrefPenWidthKey];
    _penWidthFraction = (pw >= 0.001f && pw <= 0.05f) ? pw : 0.004f;

    float mw = [ud floatForKey:kPrefMarkerWidthKey];
    _markerWidthFraction = (mw >= 0.008f && mw <= 0.12f) ? mw : 0.030f;

    if ([ud objectForKey:kPrefPenColorRKey] != nil) {
        _penColor = [UIColor colorWithRed:[ud floatForKey:kPrefPenColorRKey]
                                    green:[ud floatForKey:kPrefPenColorGKey]
                                     blue:[ud floatForKey:kPrefPenColorBKey]
                                    alpha:1.0f];
    } else {
        _penColor = [UIColor colorWithRed:0.08f green:0.08f blue:0.10f alpha:1.0f];
    }

    if ([ud objectForKey:kPrefMarkerColorRKey] != nil) {
        _markerColor = [UIColor colorWithRed:[ud floatForKey:kPrefMarkerColorRKey]
                                       green:[ud floatForKey:kPrefMarkerColorGKey]
                                        blue:[ud floatForKey:kPrefMarkerColorBKey]
                                       alpha:1.0f];
    } else {
        _markerColor = [UIColor colorWithRed:0.98f green:0.86f blue:0.12f alpha:1.0f];
    }
}

- (void)saveUserPreferences {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setInteger:_tool forKey:kPrefToolKey];
    [ud setBool:_autoTrim forKey:kPrefAutoTrimKey];
    [ud setInteger:_theme forKey:kPrefThemeKey];
    [ud setBool:_snapLines forKey:kPrefSnapLineKey];
    [ud setFloat:(float)_penWidthFraction forKey:kPrefPenWidthKey];
    [ud setFloat:(float)_markerWidthFraction forKey:kPrefMarkerWidthKey];

    CGFloat r = 0, g = 0, b = 0, a = 1;
    if ([_penColor getRed:&r green:&g blue:&b alpha:&a]) {
        [ud setFloat:(float)r forKey:kPrefPenColorRKey];
        [ud setFloat:(float)g forKey:kPrefPenColorGKey];
        [ud setFloat:(float)b forKey:kPrefPenColorBKey];
    }
    if ([_markerColor getRed:&r green:&g blue:&b alpha:&a]) {
        [ud setFloat:(float)r forKey:kPrefMarkerColorRKey];
        [ud setFloat:(float)g forKey:kPrefMarkerColorGKey];
        [ud setFloat:(float)b forKey:kPrefMarkerColorBKey];
    }
}

- (UIColor *)activeDrawColor {
    return (_tool == ReaderToolMarker) ? _markerColor : _penColor;
}

- (void)setActiveDrawColor:(UIColor *)color {
    if (!color) return;
    if (_tool == ReaderToolMarker) {
        _markerColor = color;
    } else {
        _penColor = color;
    }
    [self saveUserPreferences];
    [self syncStyleUIAndLoadedPages];
}

#pragma mark - View Setup & Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    [self updateCanvasBackground];

    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.delegate = self;
    _scrollView.minimumZoomScale = 1.0f;
    _scrollView.maximumZoomScale = 4.0f;
    _scrollView.bouncesZoom = YES;
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    _scrollView.decelerationRate = UIScrollViewDecelerationRateNormal;
    [self.view addSubview:_scrollView];

    _contentView = [[UIView alloc] initWithFrame:CGRectZero];
    _contentView.backgroundColor = [UIColor clearColor];
    [_scrollView addSubview:_contentView];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleReadDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.delegate = self;
    [_scrollView addGestureRecognizer:doubleTap];

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleReadSingleTap:)];
    singleTap.numberOfTapsRequired = 1;
    singleTap.delegate = self;
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [_scrollView addGestureRecognizer:singleTap];

    [self setupLoadingOverlay];
    [self setupDockAndHUD];
    [self setupStylePanel];
    [self setupSearchBar];

    _store = [[AnnotationStore alloc] initWithPDFPath:_pdfPath];
    _doc = [[PDFDoc alloc] initWithPath:_pdfPath];

    if (!_doc) {
        [self showFatalError:@"Could not open this PDF file."];
        return;
    }
    if (_doc.isLocked) {
        [self promptForPDFPasswordWithRetryMessage:nil];
        return;
    }
    if (_doc.pageCount <= 0) {
        [self showFatalError:@"This PDF contains no readable pages."];
        return;
    }

    [self beginPreparingDocument];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _isClosing = NO;
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_hideTimer invalidate];
    _hideTimer = nil;
    [_store flushSynchronously];

    if (self.isMovingFromParentViewController || self.isBeingDismissed) {
        _isClosing = YES;
        [_trimCancelToken cancel];
        [_searchToken cancel];
        [_exportCancelToken cancel];
        [self.navigationController setNavigationBarHidden:NO animated:animated];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Evict all offscreen pages immediately to prevent iOS 9 Jetsam kills on 1GB iPad 3!
    CGRect visible = [self currentViewportInContentCoords];
    NSArray<NSNumber *> *keys = [_loadedPages allKeys];
    for (NSNumber *k in keys) {
        NSInteger idx = [k integerValue];
        if (idx >= 0 && (NSUInteger)idx < _pageFrames.count) {
            CGRect pf = [_pageFrames[(NSUInteger)idx] CGRectValue];
            if (!CGRectIntersectsRect(pf, CGRectInset(visible, 0.0f, -80.0f))) {
                PageView *pv = _loadedPages[k];
                [pv releaseContent];
                [pv removeFromSuperview];
                [_loadedPages removeObjectForKey:k];
            }
        }
    }
}

- (void)updateCanvasBackground {
    if (_theme == PDFReadingThemeSepia) {
        self.view.backgroundColor = [UIColor colorWithRed:0.24f green:0.21f blue:0.18f alpha:1.0f];
    } else if (_theme == PDFReadingThemeNight) {
        self.view.backgroundColor = [UIColor colorWithRed:0.06f green:0.06f blue:0.08f alpha:1.0f];
    } else {
        self.view.backgroundColor = [UIColor colorWithWhite:0.16f alpha:1.0f];
    }
}

#pragma mark - Password Unlock & Preparation

- (void)promptForPDFPasswordWithRetryMessage:(NSString *)retryMsg {
    [_loadingOverlay setHidden:NO];
    [_spinner stopAnimating];
    _progressBar.hidden = YES;
    _loadingLabel.text = retryMsg ?: @"This PDF is password-protected.";
    _overlayActionBtn.hidden = NO;
    [_overlayActionBtn setTitle:@"Enter Password" forState:UIControlStateNormal];

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Password Required"
                                                                message:(retryMsg ?: @"Enter the password to unlock this PDF.")
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.secureTextEntry = YES;
        tf.placeholder = @"Password";
    }];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Back" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [weakSelf backTapped];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Unlock" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(self) sSelf = weakSelf;
        if (!sSelf) return;
        NSString *pwd = ac.textFields.firstObject.text ?: @"";
        if ([sSelf->_doc unlockWithPassword:pwd] && sSelf->_doc.pageCount > 0) {
            sSelf->_overlayActionBtn.hidden = YES;
            [sSelf beginPreparingDocument];
        } else {
            [sSelf promptForPDFPasswordWithRetryMessage:@"Incorrect password. Please try again."];
        }
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)showFatalError:(NSString *)message {
    _loadingOverlay.hidden = NO;
    [_spinner stopAnimating];
    _progressBar.hidden = YES;
    _loadingLabel.text = message;
    _overlayActionBtn.hidden = NO;
    [_overlayActionBtn setTitle:@"Back to Library" forState:UIControlStateNormal];
}

- (void)overlayActionTapped {
    if (_exportCancelToken) {
        [_exportCancelToken cancel];
        return;
    }
    if (_doc && _doc.isLocked) {
        [self promptForPDFPasswordWithRetryMessage:nil];
        return;
    }
    [self backTapped];
}

- (void)beginPreparingDocument {
    if (!_autoTrim || [_doc hasCachedTrims]) {
        _loadingOverlay.hidden = YES;
        [self finishBuildingDocument];
        return;
    }

    _loadingOverlay.hidden = NO;
    [_spinner startAnimating];
    _progressBar.hidden = NO;
    _progressBar.progress = 0.0f;
    _overlayActionBtn.hidden = YES;
    _loadingLabel.text = [NSString stringWithFormat:@"Optimizing margins (0 / %ld)…", (long)_doc.pageCount];

    [_trimCancelToken cancel];
    PDFCancelToken *token = [[PDFCancelToken alloc] init];
    _trimCancelToken = token;
    PDFDoc *doc = _doc;
    NSInteger total = doc.pageCount;

    __weak typeof(self) weakSelf = self;
    dispatch_async([PDFDoc renderQueue], ^{
        [doc prepareTrimsWithCancelToken:token progress:^(float progress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(self) sSelf = weakSelf;
                if (!sSelf || sSelf->_isClosing || token.isCancelled) return;
                sSelf->_progressBar.progress = progress;
                NSInteger done = (NSInteger)roundf(progress * (float)total);
                sSelf->_loadingLabel.text = [NSString stringWithFormat:@"Optimizing margins (%ld / %ld)…", (long)done, (long)total];
            });
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(self) sSelf = weakSelf;
            if (!sSelf || sSelf->_isClosing || token.isCancelled || sSelf->_trimCancelToken != token) return;
            sSelf->_trimCancelToken = nil;
            [sSelf->_spinner stopAnimating];
            sSelf->_loadingOverlay.hidden = YES;
            [sSelf finishBuildingDocument];
        });
    });
}

- (void)finishBuildingDocument {
    // Re-entered after enabling Auto-Trim mid-read: keep the reader's place.
    BOOL rebuilding = _didRestoreInitialPage;
    NSInteger savedPage = _store.lastPageIndex;
    _pagesReady = YES;
    _lastLayoutSize = self.view.bounds.size;
    [self layoutPagesPreservingAnchor:rebuilding];

    if (rebuilding) {
        for (PageView *pv in [_loadedPages allValues]) {
            [pv reloadAnnotationsFromStore];
        }
    } else {
        _didRestoreInitialPage = YES;
        if (savedPage > 0 && savedPage < _doc.pageCount) {
            [self jumpToPage:savedPage animated:NO];
        }
    }

    [self updateVisiblePagesForceRender:YES];
    [self applyCurrentToolConfiguration];
    [self updateUndoRedoButtons];
    [self resetHideTimer];
}

#pragma mark - UI Construction (Dock, Style Panel, Search, Overlay)

- (UIButton *)makeDockIconButton:(UIImage *)icon action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, 38.0f, 38.0f);
    [b setImage:icon forState:UIControlStateNormal];
    b.tintColor = [UIColor colorWithWhite:0.92f alpha:1.0f];
    b.layer.cornerRadius = 9.0f;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIView *)makeDockSeparator {
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 10.0f, 1.0f, 24.0f)];
    sep.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.16f];
    return sep;
}

- (void)setupLoadingOverlay {
    // Positioned below top dock area so Back button in dock is ALWAYS tappable!
    _loadingOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    _loadingOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _loadingOverlay.backgroundColor = [UIColor colorWithWhite:0.10f alpha:0.86f];
    _loadingOverlay.hidden = YES;
    [self.view addSubview:_loadingOverlay];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    [_loadingOverlay addSubview:_spinner];

    _loadingLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _loadingLabel.textColor = [UIColor whiteColor];
    _loadingLabel.font = [UIFont systemFontOfSize:15.0f];
    _loadingLabel.textAlignment = NSTextAlignmentCenter;
    _loadingLabel.numberOfLines = 3;
    [_loadingOverlay addSubview:_loadingLabel];

    _progressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    _progressBar.progressTintColor = [UIColor colorWithRed:0.25f green:0.62f blue:1.0f alpha:1.0f];
    _progressBar.trackTintColor = [UIColor colorWithWhite:1.0f alpha:0.20f];
    _progressBar.hidden = YES;
    [_loadingOverlay addSubview:_progressBar];

    _overlayActionBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_overlayActionBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _overlayActionBtn.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.18f];
    _overlayActionBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14.0f];
    _overlayActionBtn.layer.cornerRadius = 8.0f;
    _overlayActionBtn.hidden = YES;
    [_overlayActionBtn addTarget:self action:@selector(overlayActionTapped) forControlEvents:UIControlEventTouchUpInside];
    [_loadingOverlay addSubview:_overlayActionBtn];
}

- (void)setupDockAndHUD {
    _dockContainer = [[UIView alloc] initWithFrame:CGRectMake(12.0f, 26.0f, 640.0f, 46.0f)];
    _dockContainer.backgroundColor = [UIColor colorWithWhite:0.11f alpha:0.93f];
    _dockContainer.layer.cornerRadius = 14.0f;
    _dockContainer.layer.borderWidth = 0.5f;
    _dockContainer.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.16f].CGColor;
    _dockContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    _dockContainer.layer.shadowOpacity = 0.35f;
    _dockContainer.layer.shadowOffset = CGSizeMake(0.0f, 4.0f);
    _dockContainer.layer.shadowRadius = 10.0f;
    // Added AFTER `_loadingOverlay` so Back button is NEVER blocked!
    [self.view addSubview:_dockContainer];

    _dockScroll = [[UIScrollView alloc] initWithFrame:_dockContainer.bounds];
    _dockScroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dockScroll.showsHorizontalScrollIndicator = NO;
    _dockScroll.showsVerticalScrollIndicator = NO;
    _dockScroll.bounces = YES;
    [_dockContainer addSubview:_dockScroll];

    _backBtn     = [self makeDockIconButton:PDFIconBack() action:@selector(backTapped)];
    _gridBtn     = [self makeDockIconButton:PDFIconGrid() action:@selector(gridTapped)];
    _readBtn     = [self makeDockIconButton:PDFIconRead() action:@selector(readToolTapped)];
    _penBtn      = [self makeDockIconButton:PDFIconPen() action:@selector(penToolTapped)];
    _markerBtn   = [self makeDockIconButton:PDFIconMarker() action:@selector(markerToolTapped)];
    _eraserBtn   = [self makeDockIconButton:PDFIconEraser() action:@selector(eraserToolTapped)];
    _noteBtn     = [self makeDockIconButton:PDFIconNote() action:@selector(noteToolTapped)];

    _colorBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _colorBtn.frame = CGRectMake(0, 0, 38.0f, 38.0f);
    [_colorBtn addTarget:self action:@selector(colorButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    _colorInnerDisc = [[UIView alloc] initWithFrame:CGRectMake(7.0f, 7.0f, 24.0f, 24.0f)];
    _colorInnerDisc.userInteractionEnabled = NO;
    _colorInnerDisc.layer.cornerRadius = 12.0f;
    _colorInnerDisc.layer.borderWidth = 2.0f;
    _colorInnerDisc.layer.borderColor = [UIColor whiteColor].CGColor;
    [_colorBtn addSubview:_colorInnerDisc];

    _undoBtn     = [self makeDockIconButton:PDFIconUndo() action:@selector(undoTapped)];
    _redoBtn     = [self makeDockIconButton:PDFIconRedo() action:@selector(redoTapped)];
    _trashBtn    = [self makeDockIconButton:PDFIconTrash() action:@selector(trashTapped)];
    _bookmarkBtn = [self makeDockIconButton:PDFIconBookmark(NO) action:@selector(bookmarkTapped)];
    _searchBtn   = [self makeDockIconButton:PDFIconSearch() action:@selector(searchButtonTapped)];
    _optionsBtn  = [self makeDockIconButton:PDFIconCrop() action:@selector(optionsTapped)];
    _optionsBtn.accessibilityLabel = @"Reader options";
    _shareBtn    = [self makeDockIconButton:PDFIconShare() action:@selector(shareTapped)];

    NSArray *items = @[
        _backBtn, _gridBtn, [self makeDockSeparator],
        _readBtn, _penBtn, _markerBtn, _eraserBtn, _noteBtn, _colorBtn, [self makeDockSeparator],
        _undoBtn, _redoBtn, _trashBtn, [self makeDockSeparator],
        _bookmarkBtn, _searchBtn, _optionsBtn, _shareBtn
    ];

    CGFloat x = 6.0f;
    for (UIView *v in items) {
        if (v.bounds.size.width <= 2.0f) {
            v.frame = CGRectMake(x + 3.0f, 11.0f, 1.0f, 24.0f);
            x += 7.0f;
        } else {
            v.frame = CGRectMake(x, 4.0f, 38.0f, 38.0f);
            x += 40.0f;
        }
        [_dockScroll addSubview:v];
    }
    _dockScroll.contentSize = CGSizeMake(x + 4.0f, 46.0f);

    // Case-friendly left edge pull tab when dock is hidden
    _edgeTab = [UIButton buttonWithType:UIButtonTypeCustom];
    _edgeTab.frame = CGRectMake(0.0f, 120.0f, 30.0f, 72.0f);
    _edgeTab.backgroundColor = [UIColor colorWithWhite:0.12f alpha:0.86f];
    _edgeTab.tintColor = [UIColor whiteColor];
    [_edgeTab setImage:PDFIconChevron() forState:UIControlStateNormal];
    _edgeTab.layer.cornerRadius = 10.0f;
    _edgeTab.layer.borderWidth = 0.5f;
    _edgeTab.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.20f].CGColor;
    _edgeTab.hidden = YES;
    [_edgeTab addTarget:self action:@selector(edgeTabTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_edgeTab];

    // Interactive bottom page pill (tapping opens Page Grid / TOC / Bookmarks!)
    _pagePillBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _pagePillBtn.backgroundColor = [UIColor colorWithWhite:0.11f alpha:0.88f];
    [_pagePillBtn setTitleColor:[UIColor colorWithWhite:0.95f alpha:1.0f] forState:UIControlStateNormal];
    _pagePillBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13.0f];
    _pagePillBtn.layer.cornerRadius = 14.0f;
    _pagePillBtn.layer.borderWidth = 0.5f;
    _pagePillBtn.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.16f].CGColor;
    [_pagePillBtn addTarget:self action:@selector(gridTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_pagePillBtn];
}

- (void)setupStylePanel {
    _stylePanel = [[UIView alloc] initWithFrame:CGRectMake(0, 78.0f, 308.0f, 212.0f)];
    _stylePanel.backgroundColor = [UIColor colorWithWhite:0.13f alpha:0.96f];
    _stylePanel.layer.cornerRadius = 14.0f;
    _stylePanel.layer.borderWidth = 0.5f;
    _stylePanel.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.18f].CGColor;
    _stylePanel.layer.shadowColor = [UIColor blackColor].CGColor;
    _stylePanel.layer.shadowOpacity = 0.40f;
    _stylePanel.layer.shadowOffset = CGSizeMake(0.0f, 6.0f);
    _stylePanel.layer.shadowRadius = 14.0f;
    _stylePanel.hidden = YES;
    _stylePanel.alpha = 0.0f;
    [self.view addSubview:_stylePanel];

    NSArray<UIColor *> *presets = @[
        [UIColor colorWithRed:0.08f green:0.08f blue:0.10f alpha:1.0f], // Ink Black
        [UIColor colorWithRed:0.12f green:0.24f blue:0.52f alpha:1.0f], // Navy
        [UIColor colorWithRed:0.12f green:0.45f blue:0.96f alpha:1.0f], // Royal Blue
        [UIColor colorWithRed:0.88f green:0.16f blue:0.18f alpha:1.0f], // Crimson
        [UIColor colorWithRed:0.12f green:0.66f blue:0.32f alpha:1.0f], // Emerald
        [UIColor colorWithRed:0.96f green:0.52f blue:0.10f alpha:1.0f], // Orange
        [UIColor colorWithRed:0.58f green:0.24f blue:0.86f alpha:1.0f], // Violet
        [UIColor colorWithRed:0.98f green:0.86f blue:0.12f alpha:1.0f], // Highlighter Yellow
        [UIColor colorWithRed:0.98f green:0.98f blue:0.98f alpha:1.0f], // White
    ];

    CGFloat sx = 14.0f;
    for (NSUInteger i = 0; i < presets.count; i++) {
        UIButton *sw = [UIButton buttonWithType:UIButtonTypeCustom];
        sw.frame = CGRectMake(sx, 14.0f, 26.0f, 26.0f);
        sw.backgroundColor = presets[i];
        sw.tag = (NSInteger)i;
        sw.layer.cornerRadius = 13.0f;
        sw.layer.borderWidth = 1.5f;
        sw.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.35f].CGColor;
        [sw addTarget:self action:@selector(presetSwatchTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_stylePanel addSubview:sw];
        [_swatchButtons addObject:sw];
        sx += 31.5f;
    }

    UILabel *hueLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0f, 48.0f, 90.0f, 16.0f)];
    hueLabel.text = @"Custom Hue";
    hueLabel.font = [UIFont systemFontOfSize:11.5f];
    hueLabel.textColor = [UIColor colorWithWhite:0.75f alpha:1.0f];
    [_stylePanel addSubview:hueLabel];

    _hueSlider = [[UISlider alloc] initWithFrame:CGRectMake(14.0f, 65.0f, 280.0f, 24.0f)];
    _hueSlider.minimumValue = 0.0f;
    _hueSlider.maximumValue = 1.0f;
    UIImage *rainbow = PDFRainbowTrackImage(CGSizeMake(260.0f, 8.0f));
    [_hueSlider setMinimumTrackImage:rainbow forState:UIControlStateNormal];
    [_hueSlider setMaximumTrackImage:rainbow forState:UIControlStateNormal];
    [_hueSlider addTarget:self action:@selector(hueSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_stylePanel addSubview:_hueSlider];

    _widthTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0f, 94.0f, 160.0f, 16.0f)];
    _widthTitleLabel.text = @"Thickness";
    _widthTitleLabel.font = [UIFont systemFontOfSize:11.5f];
    _widthTitleLabel.textColor = [UIColor colorWithWhite:0.75f alpha:1.0f];
    [_stylePanel addSubview:_widthTitleLabel];

    _widthSlider = [[UISlider alloc] initWithFrame:CGRectMake(14.0f, 112.0f, 182.0f, 26.0f)];
    _widthSlider.minimumValue = 0.0f;
    _widthSlider.maximumValue = 1.0f;
    _widthSlider.minimumTrackTintColor = [UIColor colorWithRed:0.28f green:0.64f blue:1.0f alpha:1.0f];
    [_widthSlider addTarget:self action:@selector(widthSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_stylePanel addSubview:_widthSlider];

    _strokePreview = [[PDFStrokePreviewView alloc] initWithFrame:CGRectMake(204.0f, 106.0f, 90.0f, 34.0f)];
    _strokePreview.backgroundColor = [UIColor clearColor];
    [_stylePanel addSubview:_strokePreview];

    UILabel *snapLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0f, 156.0f, 210.0f, 36.0f)];
    snapLabel.text = @"Hold to Snap Straight Line\n(Pause finger 0.4s at end of stroke)";
    snapLabel.numberOfLines = 2;
    snapLabel.font = [UIFont systemFontOfSize:11.5f];
    snapLabel.textColor = [UIColor colorWithWhite:0.82f alpha:1.0f];
    [_stylePanel addSubview:snapLabel];

    _snapSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _snapSwitch.on = _snapLines;
    _snapSwitch.onTintColor = [UIColor colorWithRed:0.24f green:0.62f blue:1.0f alpha:1.0f];
    [_snapSwitch addTarget:self action:@selector(snapSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    CGRect sf = _snapSwitch.frame;
    sf.origin = CGPointMake(294.0f - sf.size.width, 159.0f);
    _snapSwitch.frame = sf;
    [_stylePanel addSubview:_snapSwitch];
}

- (void)setupSearchBar {
    _searchContainer = [[UIView alloc] initWithFrame:CGRectMake(12.0f, 78.0f, 460.0f, 44.0f)];
    _searchContainer.backgroundColor = [UIColor colorWithWhite:0.13f alpha:0.96f];
    _searchContainer.layer.cornerRadius = 12.0f;
    _searchContainer.layer.borderWidth = 0.5f;
    _searchContainer.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.18f].CGColor;
    _searchContainer.hidden = YES;
    [self.view addSubview:_searchContainer];

    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(4.0f, 4.0f, 250.0f, 36.0f)];
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.barStyle = UIBarStyleBlack;
    _searchBar.placeholder = @"Find text in PDF…";
    _searchBar.delegate = self;
    [_searchContainer addSubview:_searchBar];

    _searchStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(258.0f, 0.0f, 92.0f, 44.0f)];
    _searchStatusLabel.font = [UIFont systemFontOfSize:12.0f];
    _searchStatusLabel.textColor = [UIColor colorWithWhite:0.80f alpha:1.0f];
    _searchStatusLabel.textAlignment = NSTextAlignmentRight;
    [_searchContainer addSubview:_searchStatusLabel];

    _searchPrevBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_searchPrevBtn setTitle:@"◀" forState:UIControlStateNormal];
    [_searchPrevBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _searchPrevBtn.frame = CGRectMake(354.0f, 4.0f, 34.0f, 36.0f);
    [_searchPrevBtn addTarget:self action:@selector(searchPrevTapped) forControlEvents:UIControlEventTouchUpInside];
    [_searchContainer addSubview:_searchPrevBtn];

    _searchNextBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_searchNextBtn setTitle:@"▶" forState:UIControlStateNormal];
    [_searchNextBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _searchNextBtn.frame = CGRectMake(388.0f, 4.0f, 34.0f, 36.0f);
    [_searchNextBtn addTarget:self action:@selector(searchNextTapped) forControlEvents:UIControlEventTouchUpInside];
    [_searchContainer addSubview:_searchNextBtn];

    UIButton *closeSearch = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeSearch setTitle:@"✕" forState:UIControlStateNormal];
    [closeSearch setTitleColor:[UIColor colorWithWhite:0.75f alpha:1.0f] forState:UIControlStateNormal];
    closeSearch.titleLabel.font = [UIFont boldSystemFontOfSize:15.0f];
    closeSearch.frame = CGRectMake(424.0f, 4.0f, 32.0f, 36.0f);
    [closeSearch addTarget:self action:@selector(closeSearchTapped) forControlEvents:UIControlEventTouchUpInside];
    [_searchContainer addSubview:closeSearch];
}

#pragma mark - Responsive Layout & Rotation Preservation

- (void)layoutHUDChrome {
    CGSize boundsSz = self.view.bounds.size;
    CGFloat topY = 24.0f;

    CGFloat desiredDockW = _dockScroll.contentSize.width;
    CGFloat maxDockW = MAX(260.0f, boundsSz.width - 20.0f);
    CGFloat dockW = MIN(desiredDockW, maxDockW);
    _dockContainer.frame = CGRectMake(floorf((float)((boundsSz.width - dockW) * 0.5f)), topY, dockW, 46.0f);
    _dockContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_dockContainer.bounds cornerRadius:14.0f].CGPath;

    _edgeTab.frame = CGRectMake(-6.0f, floorf((float)(boundsSz.height * 0.42f)), 34.0f, 72.0f);

    // Style panel aligned near _colorBtn
    CGRect colorInView = [_dockScroll convertRect:_colorBtn.frame toView:self.view];
    CGFloat panelW = MIN(308.0f, boundsSz.width - 20.0f);
    CGFloat panelX = colorInView.origin.x + colorInView.size.width * 0.5f - panelW * 0.5f;
    panelX = MAX(10.0f, MIN(boundsSz.width - panelW - 10.0f, panelX));
    _stylePanel.frame = CGRectMake(floorf((float)panelX), CGRectGetMaxY(_dockContainer.frame) + 8.0f, panelW, 212.0f);
    _stylePanel.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_stylePanel.bounds cornerRadius:14.0f].CGPath;

    // Search bar container
    CGFloat searchW = MIN(462.0f, boundsSz.width - 20.0f);
    CGFloat searchX = floorf((float)((boundsSz.width - searchW) * 0.5f));
    _searchContainer.frame = CGRectMake(searchX, CGRectGetMaxY(_dockContainer.frame) + 8.0f, searchW, 44.0f);
    CGFloat controlsW = 198.0f;
    _searchBar.frame = CGRectMake(4.0f, 4.0f, MAX(110.0f, searchW - controlsW - 8.0f), 36.0f);
    _searchStatusLabel.frame = CGRectMake(CGRectGetMaxX(_searchBar.frame) + 2.0f, 0.0f, 88.0f, 44.0f);
    _searchPrevBtn.frame = CGRectMake(searchW - 104.0f, 4.0f, 34.0f, 36.0f);
    _searchNextBtn.frame = CGRectMake(searchW - 70.0f, 4.0f, 34.0f, 36.0f);
    UIView *closeBtn = _searchContainer.subviews.lastObject;
    closeBtn.frame = CGRectMake(searchW - 36.0f, 4.0f, 32.0f, 36.0f);

    // Loading overlay subviews
    CGFloat cx = boundsSz.width * 0.5f;
    CGFloat cy = boundsSz.height * 0.5f;
    _spinner.center = CGPointMake(cx, cy - 30.0f);
    _loadingLabel.frame = CGRectMake(32.0f, cy + 4.0f, boundsSz.width - 64.0f, 60.0f);
    _progressBar.frame = CGRectMake(cx - 120.0f, cy + 68.0f, 240.0f, 4.0f);
    _overlayActionBtn.frame = CGRectMake(cx - 85.0f, cy + 84.0f, 170.0f, 38.0f);

    [self updatePagePillFrame];
}

- (void)updatePagePillFrame {
    [_pagePillBtn sizeToFit];
    CGFloat w = MAX(86.0f, _pagePillBtn.bounds.size.width + 28.0f);
    CGFloat h = 28.0f;
    CGSize boundsSz = self.view.bounds.size;
    _pagePillBtn.frame = CGRectMake(floorf((float)((boundsSz.width - w) * 0.5f)),
                                    boundsSz.height - h - 14.0f,
                                    w,
                                    h);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutHUDChrome];

    if (_pagesReady && !CGSizeEqualToSize(self.view.bounds.size, _lastLayoutSize)) {
        _lastLayoutSize = self.view.bounds.size;
        [self layoutPagesPreservingAnchor:YES];
        [self updateVisiblePagesForceRender:YES];
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    // Capture exact reading anchor BEFORE zoomScale changes!
    NSInteger anchorPage = 0;
    CGFloat anchorFraction = 0.0f;
    if (_pagesReady && _pageFrames.count > 0) {
        [self captureScrollAnchorPage:&anchorPage fraction:&anchorFraction];
    }

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (self->_pagesReady) {
            self->_lastLayoutSize = size;
            [self->_scrollView setZoomScale:1.0f animated:NO];
            self->_scrollView.contentInset = UIEdgeInsetsZero;
            [self rebuildPageFramesForContainerSize:size];
            [self restoreScrollAnchorPage:anchorPage fraction:anchorFraction forContainerSize:size];
        }
        [self layoutHUDChrome];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (self->_pagesReady) {
            [self updateVisiblePagesForceRender:YES];
        }
    }];
}

- (void)captureScrollAnchorPage:(NSInteger *)outPage fraction:(CGFloat *)outFraction {
    CGFloat scale = MAX(_scrollView.zoomScale, 0.01f);
    CGFloat unscaledTop = (_scrollView.contentOffset.y + _scrollView.contentInset.top) / scale;
    NSInteger foundPage = 0;
    CGFloat frac = 0.0f;

    for (NSUInteger i = 0; i < _pageFrames.count; i++) {
        CGRect pf = [_pageFrames[i] CGRectValue];
        if (CGRectGetMaxY(pf) >= unscaledTop) {
            foundPage = (NSInteger)i;
            if (pf.size.height > 1.0f) {
                frac = (unscaledTop - pf.origin.y) / pf.size.height;
                frac = MAX(-0.2f, MIN(1.0f, frac));
            }
            break;
        }
    }
    *outPage = foundPage;
    *outFraction = frac;
}

- (void)restoreScrollAnchorPage:(NSInteger)anchorPage fraction:(CGFloat)anchorFraction forContainerSize:(CGSize)containerSize {
    if (anchorPage < 0 || (NSUInteger)anchorPage >= _pageFrames.count) return;
    CGRect pf = [_pageFrames[(NSUInteger)anchorPage] CGRectValue];
    CGFloat rawY = pf.origin.y + anchorFraction * pf.size.height;
    CGFloat maxOffset = MAX(0.0f, _scrollView.contentSize.height - containerSize.height);
    CGFloat clampedY = MAX(0.0f, MIN(maxOffset, rawY));
    _scrollView.contentOffset = CGPointMake(0.0f, clampedY);
}

- (void)rebuildPageFramesForContainerSize:(CGSize)containerSize {
    [_pageFrames removeAllObjects];
    NSInteger count = _doc.pageCount;
    if (count <= 0 || containerSize.width < 20.0f) return;

    CGFloat sidePad = (containerSize.width >= 600.0f) ? 18.0f : 8.0f;
    CGFloat pageW = MAX(60.0f, containerSize.width - sidePad * 2.0f);
    CGFloat y = 80.0f; // Top breathing room below floating dock
    CGFloat gap = 14.0f;

    for (NSInteger i = 0; i < count; i++) {
        CGSize fullSz = [_doc pageSizeAtIndex:i];
        CGRect trim = [_doc trimAtIndex:i autoTrim:_autoTrim];
        CGFloat effW = MAX(1.0f, fullSz.width * trim.size.width);
        CGFloat effH = MAX(1.0f, fullSz.height * trim.size.height);
        CGFloat pageH = MAX(40.0f, floorf((float)((effH / effW) * pageW)));

        CGRect frame = CGRectMake(sidePad, y, pageW, pageH);
        [_pageFrames addObject:[NSValue valueWithCGRect:frame]];

        PageView *loaded = _loadedPages[@(i)];
        if (loaded) {
            loaded.trim = trim;
            loaded.theme = _theme;
            loaded.frame = frame;
        }
        y += pageH + gap;
    }

    CGFloat totalH = y + 48.0f;
    _contentView.frame = CGRectMake(0.0f, 0.0f, containerSize.width, totalH);
    _scrollView.contentSize = CGSizeMake(containerSize.width, totalH);
}

- (void)layoutPagesPreservingAnchor:(BOOL)preserveAnchor {
    NSInteger anchorPage = 0;
    CGFloat anchorFraction = 0.0f;
    if (preserveAnchor && _pageFrames.count > 0) {
        [self captureScrollAnchorPage:&anchorPage fraction:&anchorFraction];
    }

    [_scrollView setZoomScale:1.0f animated:NO];
    _scrollView.contentInset = UIEdgeInsetsZero;
    CGSize sz = self.view.bounds.size;
    [self rebuildPageFramesForContainerSize:sz];

    if (preserveAnchor && _pageFrames.count > 0) {
        [self restoreScrollAnchorPage:anchorPage fraction:anchorFraction forContainerSize:sz];
    }
}

#pragma mark - Virtualized Page Window & Scroll/Zoom Delegates

- (CGRect)currentViewportInContentCoords {
    CGFloat scale = MAX(_scrollView.zoomScale, 0.01f);
    CGRect vis;
    vis.origin.x = (_scrollView.contentOffset.x + _scrollView.contentInset.left) / scale;
    vis.origin.y = (_scrollView.contentOffset.y + _scrollView.contentInset.top) / scale;
    vis.size.width = _scrollView.bounds.size.width / scale;
    vis.size.height = _scrollView.bounds.size.height / scale;
    return vis;
}

- (NSUInteger)firstPageEndingAtOrAfterY:(CGFloat)y {
    NSUInteger lo = 0, hi = _pageFrames.count;
    while (lo < hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        if (CGRectGetMaxY([_pageFrames[mid] CGRectValue]) < y) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}

- (NSInteger)currentCenteredPageIndex {
    if (_pageFrames.count == 0) return 0;
    CGRect vis = [self currentViewportInContentCoords];
    CGFloat midY = CGRectGetMidY(vis);

    NSUInteger i = [self firstPageEndingAtOrAfterY:midY];
    if (i == _pageFrames.count) return (NSInteger)i - 1;
    CGRect pf = [_pageFrames[i] CGRectValue];
    if (i > 0 && midY < CGRectGetMinY(pf)) {
        CGRect prev = [_pageFrames[i - 1] CGRectValue];
        if (fabs((double)(CGRectGetMidY(prev) - midY)) <=
            fabs((double)(CGRectGetMidY(pf) - midY))) return (NSInteger)i - 1;
    }
    return (NSInteger)i;
}

- (PageView *)ensurePageViewLoadedAtIndex:(NSInteger)index {
    if (index < 0 || (NSUInteger)index >= _pageFrames.count) return nil;
    PageView *pv = _loadedPages[@(index)];
    if (!pv) {
        CGRect trim = [_doc trimAtIndex:index autoTrim:_autoTrim];
        pv = [[PageView alloc] initWithDoc:_doc store:_store index:index trim:trim theme:_theme];
        pv.delegate = self;
        pv.frame = [_pageFrames[(NSUInteger)index] CGRectValue];
        pv.tool = _tool;
        pv.drawColor = [self activeDrawColor];
        pv.penWidthFraction = _penWidthFraction;
        pv.markerWidthFraction = _markerWidthFraction;
        pv.snapStraightLines = _snapLines;
        [_contentView addSubview:pv];
        _loadedPages[@(index)] = pv;
    }
    return pv;
}

- (void)updateVisiblePagesForceRender:(BOOL)forceRender {
    if (!_pagesReady || _pageFrames.count == 0) return;

    CGRect vis = [self currentViewportInContentCoords];
    CGFloat vh = MAX(vis.size.height, 300.0f);
    // Tuned specifically for iPad 3 1GB RAM: render ±0.65 viewport, keep ±1.20 viewport (~3-4 pages max in memory!)
    CGRect renderWindow = CGRectInset(vis, 0.0f, -vh * 0.65f);
    CGRect keepWindow   = CGRectInset(vis, 0.0f, -vh * 1.25f);
    CGFloat zoom = _scrollView.zoomScale;

    NSUInteger first = [self firstPageEndingAtOrAfterY:CGRectGetMinY(renderWindow)];
    for (NSUInteger i = first; i < _pageFrames.count; i++) {
        CGRect pf = [_pageFrames[i] CGRectValue];
        if (CGRectGetMinY(pf) > CGRectGetMaxY(renderWindow)) break;
        if (CGRectIntersectsRect(pf, renderWindow)) {
            PageView *pv = [self ensurePageViewLoadedAtIndex:(NSInteger)i];
            if (forceRender || ![pv hasLoadedBitmap]) {
                [pv renderContentWithZoomScale:zoom];
            }
        }
    }
    for (NSNumber *key in [_loadedPages allKeys]) {
        PageView *pv = _loadedPages[key];
        if (!CGRectIntersectsRect(pv.frame, keepWindow)) {
            [pv releaseContent];
            [pv removeFromSuperview];
            [_loadedPages removeObjectForKey:key];
        }
    }

    NSInteger curPage = [self currentCenteredPageIndex];
    _store.lastPageIndex = curPage;

    NSString *pillTitle = [NSString stringWithFormat:@"%ld / %ld", (long)(curPage + 1), (long)_doc.pageCount];
    if (![[_pagePillBtn titleForState:UIControlStateNormal] isEqualToString:pillTitle]) {
        [_pagePillBtn setTitle:pillTitle forState:UIControlStateNormal];
        [self updatePagePillFrame];
    }
    [self updateBookmarkButtonForPage:curPage];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self updateVisiblePagesForceRender:NO];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    // Cancel any uncommitted touch on loaded pages so 2-finger pan NEVER leaves dots or erases!
    for (PageView *pv in [_loadedPages allValues]) {
        [pv cancelActiveTouchIfNeeded];
    }
    if (_panelOpen) [self setStylePanelOpen:NO animated:YES];
    [self resetHideTimer];
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view {
    for (PageView *pv in [_loadedPages allValues]) {
        [pv cancelActiveTouchIfNeeded];
    }
    if (_panelOpen) [self setStylePanelOpen:NO animated:YES];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _contentView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    CGSize boundsSize = scrollView.bounds.size;
    CGSize contentSize = scrollView.contentSize;
    CGFloat offsetX = (boundsSize.width > contentSize.width) ? floorf((float)((boundsSize.width - contentSize.width) * 0.5f)) : 0.0f;
    CGFloat offsetY = (boundsSize.height > contentSize.height) ? floorf((float)((boundsSize.height - contentSize.height) * 0.5f)) : 0.0f;
    scrollView.contentInset = UIEdgeInsetsMake(offsetY, offsetX, offsetY, offsetX);
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale {
    // Re-sharpen visible pages at the new zoom scale!
    CGRect vis = [self currentViewportInContentCoords];
    for (NSNumber *k in _loadedPages) {
        PageView *pv = _loadedPages[k];
        if (CGRectIntersectsRect(pv.frame, vis)) {
            [pv renderContentWithZoomScale:scale];
        }
    }
}

- (void)jumpToPage:(NSInteger)pageIndex animated:(BOOL)animated {
    if (!_pagesReady || pageIndex < 0 || (NSUInteger)pageIndex >= _pageFrames.count) return;
    if (_scrollView.zoomScale != 1.0f) {
        [_scrollView setZoomScale:1.0f animated:NO];
        _scrollView.contentInset = UIEdgeInsetsZero;
    }
    CGRect pf = [_pageFrames[(NSUInteger)pageIndex] CGRectValue];
    CGFloat topMargin = _dockHidden ? 18.0f : 78.0f;
    CGFloat targetY = PDFPageJumpOffset(pf.origin.y, pf.size.height, _scrollView.bounds.size.height,
                                        _scrollView.contentSize.height, topMargin);
    [_scrollView setContentOffset:CGPointMake(0.0f, targetY) animated:animated];
    if (!animated) {
        [self updateVisiblePagesForceRender:NO];
    }
}

#pragma mark - Read Mode Tap & Double-Tap Gestures

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (_tool != ReaderToolScroll) return NO;
    UIView *hit = touch.view;
    while (hit && hit != self.view) {
        if (hit == _dockContainer || hit == _stylePanel || hit == _searchContainer ||
            hit == _pagePillBtn || hit == _edgeTab ||
            [NSStringFromClass([hit class]) isEqualToString:@"PDFNoteBadgeView"]) {
            return NO;
        }
        hit = hit.superview;
    }
    return YES;
}

- (void)handleReadSingleTap:(UITapGestureRecognizer *)gr {
    if (_tool != ReaderToolScroll || !_pagesReady) return;
    [self setDockHidden:!_dockHidden animated:YES];
}

- (void)handleReadDoubleTap:(UITapGestureRecognizer *)gr {
    if (_tool != ReaderToolScroll || !_pagesReady) return;
    if (_scrollView.zoomScale > 1.15f) {
        [_scrollView setZoomScale:1.0f animated:YES];
    } else {
        CGPoint pt = [gr locationInView:_contentView];
        CGFloat targetScale = 2.2f;
        CGFloat w = _scrollView.bounds.size.width / targetScale;
        CGFloat h = _scrollView.bounds.size.height / targetScale;
        CGRect zoomRect = CGRectMake(pt.x - w * 0.5f, pt.y - h * 0.5f, w, h);
        [_scrollView zoomToRect:zoomRect animated:YES];
    }
}

#pragma mark - Dock Visibility & Auto-Hide Timer (Leak-Free)

- (void)resetHideTimer {
    [_hideTimer invalidate];
    _hideTimer = nil;
    if (_isClosing || _dockHidden || _panelOpen || !_searchContainer.hidden) return;
    // Only auto-hide after 8s in Read mode; keep toolbar steady while actively annotating!
    if (_tool == ReaderToolScroll) {
        _hideTimer = [PDFWeakTimerTarget scheduledTimerWithTimeInterval:8.0
                                                                 target:self
                                                               selector:@selector(autoHideTimerFired:)
                                                                repeats:NO];
    }
}

- (void)autoHideTimerFired:(NSTimer *)timer {
    _hideTimer = nil;
    if (_isClosing || _panelOpen || !_searchContainer.hidden || _tool != ReaderToolScroll) return;
    [self setDockHidden:YES animated:YES];
}

- (void)setDockHidden:(BOOL)hidden animated:(BOOL)animated {
    _dockHidden = hidden;
    [_hideTimer invalidate];
    _hideTimer = nil;

    if (hidden && _panelOpen) {
        [self setStylePanelOpen:NO animated:NO];
    }

    if (!hidden) {
        _dockContainer.hidden = NO;
        _edgeTab.hidden = YES;
    }

    void (^changes)(void) = ^{
        self->_dockContainer.alpha = hidden ? 0.0f : 1.0f;
        self->_pagePillBtn.alpha = hidden ? 0.45f : 1.0f;
    };
    void (^done)(BOOL) = ^(BOOL finished) {
        if (self->_dockHidden) {
            self->_dockContainer.hidden = YES;
            self->_edgeTab.hidden = NO;
        } else {
            [self resetHideTimer];
        }
    };

    if (animated) {
        [UIView animateWithDuration:0.22 animations:changes completion:done];
    } else {
        changes();
        done(YES);
    }
}

- (void)edgeTabTapped {
    [self setDockHidden:NO animated:YES];
}

#pragma mark - Tool Switching & Style Panel

- (void)readToolTapped   { [self selectTool:ReaderToolScroll]; }
- (void)penToolTapped    { if (_tool == ReaderToolPen) [self colorButtonTapped]; else [self selectTool:ReaderToolPen]; }
- (void)markerToolTapped { if (_tool == ReaderToolMarker) [self colorButtonTapped]; else [self selectTool:ReaderToolMarker]; }
- (void)eraserToolTapped { [self selectTool:ReaderToolEraser]; }
- (void)noteToolTapped   { [self selectTool:ReaderToolNote]; }

- (void)selectTool:(ReaderTool)tool {
    _tool = tool;
    [self saveUserPreferences];
    if (tool == ReaderToolScroll || tool == ReaderToolEraser) {
        [self setStylePanelOpen:NO animated:YES];
    }
    [self applyCurrentToolConfiguration];
    [self resetHideTimer];
}

- (void)applyCurrentToolConfiguration {
    BOOL isScroll = (_tool == ReaderToolScroll);
    _scrollView.panGestureRecognizer.minimumNumberOfTouches = isScroll ? 1 : 2;
    _scrollView.delaysContentTouches = isScroll;

    NSArray<UIButton *> *toolButtons = @[ _readBtn, _penBtn, _markerBtn, _eraserBtn, _noteBtn ];
    NSArray<NSNumber *> *toolValues  = @[ @(ReaderToolScroll), @(ReaderToolPen), @(ReaderToolMarker), @(ReaderToolEraser), @(ReaderToolNote) ];
    UIColor *activeBg = [UIColor colorWithRed:0.22f green:0.56f blue:0.98f alpha:1.0f];

    for (NSUInteger i = 0; i < toolButtons.count; i++) {
        UIButton *b = toolButtons[i];
        BOOL active = ([toolValues[i] integerValue] == _tool);
        b.backgroundColor = active ? activeBg : [UIColor clearColor];
        b.tintColor = active ? [UIColor whiteColor] : [UIColor colorWithWhite:0.90f alpha:1.0f];
    }

    [self syncStyleUIAndLoadedPages];
}

- (void)syncStyleUIAndLoadedPages {
    UIColor *activeColor = [self activeDrawColor];
    _colorInnerDisc.backgroundColor = activeColor;

    CGFloat h = 0.0f, s = 0.0f, b = 0.0f, a = 1.0f;
    if ([activeColor getHue:&h saturation:&s brightness:&b alpha:&a] && s > 0.05f) {
        _hueSlider.value = (float)h;
    }

    BOOL isMarker = (_tool == ReaderToolMarker);
    CGFloat minF = isMarker ? 0.010f : 0.0012f;
    CGFloat maxF = isMarker ? 0.080f : 0.0180f;
    CGFloat curF = isMarker ? _markerWidthFraction : _penWidthFraction;
    _widthSlider.value = (float)MAX(0.0f, MIN(1.0f, (curF - minF) / (maxF - minF)));
    _widthTitleLabel.text = isMarker ? @"Marker Width" : @"Pen Width";

    _strokePreview.strokeColor = activeColor;
    _strokePreview.strokeAlpha = isMarker ? 0.42f : 1.0f;
    _strokePreview.lineWidthPts = curF * 580.0f;
    [_strokePreview setNeedsDisplay];

    for (UIButton *sw in _swatchButtons) {
        CGFloat r1=0, g1=0, b1=0, r2=0, g2=0, b2=0;
        [sw.backgroundColor getRed:&r1 green:&g1 blue:&b1 alpha:NULL];
        [activeColor getRed:&r2 green:&g2 blue:&b2 alpha:NULL];
        BOOL match = (fabs(r1 - r2) < 0.03 && fabs(g1 - g2) < 0.03 && fabs(b1 - b2) < 0.03);
        sw.layer.borderWidth = match ? 3.0f : 1.2f;
        sw.layer.borderColor = match ? [UIColor whiteColor].CGColor : [UIColor colorWithWhite:1.0f alpha:0.32f].CGColor;
    }

    for (PageView *pv in [_loadedPages allValues]) {
        pv.tool = _tool;
        pv.drawColor = activeColor;
        pv.penWidthFraction = _penWidthFraction;
        pv.markerWidthFraction = _markerWidthFraction;
        pv.snapStraightLines = _snapLines;
    }
}

- (void)colorButtonTapped {
    if (_tool != ReaderToolPen && _tool != ReaderToolMarker) {
        _tool = ReaderToolPen;
        [self applyCurrentToolConfiguration];
    }
    [self setStylePanelOpen:!_panelOpen animated:YES];
}

- (void)setStylePanelOpen:(BOOL)open animated:(BOOL)animated {
    _panelOpen = open;
    if (open) {
        [self layoutHUDChrome];
        [self syncStyleUIAndLoadedPages];
        _stylePanel.hidden = NO;
        [_hideTimer invalidate];
        _hideTimer = nil;
    }

    void (^anim)(void) = ^{
        self->_stylePanel.alpha = open ? 1.0f : 0.0f;
    };
    void (^done)(BOOL) = ^(BOOL finished) {
        if (!self->_panelOpen) {
            self->_stylePanel.hidden = YES;
            [self resetHideTimer];
        }
    };

    if (animated) {
        [UIView animateWithDuration:0.18 animations:anim completion:done];
    } else {
        anim();
        done(YES);
    }
}

- (void)presetSwatchTapped:(UIButton *)sender {
    [self setActiveDrawColor:sender.backgroundColor];
}

- (void)hueSliderChanged:(UISlider *)slider {
    UIColor *c = [UIColor colorWithHue:slider.value saturation:0.90f brightness:0.92f alpha:1.0f];
    [self setActiveDrawColor:c];
}

- (void)widthSliderChanged:(UISlider *)slider {
    BOOL isMarker = (_tool == ReaderToolMarker);
    CGFloat minF = isMarker ? 0.010f : 0.0012f;
    CGFloat maxF = isMarker ? 0.080f : 0.0180f;
    CGFloat frac = minF + slider.value * (maxF - minF);
    if (isMarker) {
        _markerWidthFraction = frac;
    } else {
        _penWidthFraction = frac;
    }
    [self saveUserPreferences];
    [self syncStyleUIAndLoadedPages];
}

- (void)snapSwitchChanged:(UISwitch *)sw {
    _snapLines = sw.isOn;
    [self saveUserPreferences];
    [self syncStyleUIAndLoadedPages];
}

#pragma mark - Undo, Redo, Clear Page & Bookmarks

- (void)updateUndoRedoButtons {
    BOOL u = [_store canUndo];
    BOOL r = [_store canRedo];
    _undoBtn.enabled = u;
    _undoBtn.alpha = u ? 1.0f : 0.35f;
    _redoBtn.enabled = r;
    _redoBtn.alpha = r ? 1.0f : 0.35f;
}

- (void)undoTapped {
    NSInteger affectedPage = [_store undoReturningPage];
    if (affectedPage == NSNotFound) return;
    PageView *pv = _loadedPages[@(affectedPage)];
    [pv reloadAnnotationsFromStore];
    [self updateUndoRedoButtons];

    // If the undone edit was on an offscreen page, scroll to show the user!
    CGRect vis = [self currentViewportInContentCoords];
    if (affectedPage >= 0 && (NSUInteger)affectedPage < _pageFrames.count) {
        CGRect pf = [_pageFrames[(NSUInteger)affectedPage] CGRectValue];
        if (!CGRectIntersectsRect(pf, vis)) {
            [self jumpToPage:affectedPage animated:YES];
        }
    }
}

- (void)redoTapped {
    NSInteger affectedPage = [_store redoReturningPage];
    if (affectedPage == NSNotFound) return;
    PageView *pv = _loadedPages[@(affectedPage)];
    [pv reloadAnnotationsFromStore];
    [self updateUndoRedoButtons];

    CGRect vis = [self currentViewportInContentCoords];
    if (affectedPage >= 0 && (NSUInteger)affectedPage < _pageFrames.count) {
        CGRect pf = [_pageFrames[(NSUInteger)affectedPage] CGRectValue];
        if (!CGRectIntersectsRect(pf, vis)) {
            [self jumpToPage:affectedPage animated:YES];
        }
    }
}

- (void)trashTapped {
    if (!_pagesReady) return;
    // Always target the currently centered visible page (NEVER an old offscreen page!)
    NSInteger targetPage = [self currentCenteredPageIndex];
    if (![_store hasAnnotationsOnPage:targetPage]) {
        UIAlertController *info = [UIAlertController alertControllerWithTitle:@"Page Is Clean"
                                                                      message:[NSString stringWithFormat:@"Page %ld has no strokes or notes to clear.", (long)(targetPage + 1)]
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [info addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:info animated:YES completion:nil];
        return;
    }

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Clear Page %ld?", (long)(targetPage + 1)]
                                                                message:@"All strokes and text notes on this page will be removed (you can Undo this)."
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Clear Page %ld", (long)(targetPage + 1)]
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
        __strong typeof(self) sSelf = weakSelf;
        if (!sSelf) return;
        [sSelf->_store clearPage:targetPage];
        [sSelf->_loadedPages[@(targetPage)] reloadAnnotationsFromStore];
        [sSelf updateUndoRedoButtons];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *pop = ac.popoverPresentationController;
    if (pop) {
        pop.sourceView = _trashBtn;
        pop.sourceRect = _trashBtn.bounds;
    }
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)updateBookmarkButtonForPage:(NSInteger)pageIndex {
    BOOL bm = [_store isPageBookmarked:pageIndex];
    [_bookmarkBtn setImage:PDFIconBookmark(bm) forState:UIControlStateNormal];
    _bookmarkBtn.tintColor = bm
        ? [UIColor colorWithRed:1.0f green:0.78f blue:0.22f alpha:1.0f]
        : [UIColor colorWithWhite:0.92f alpha:1.0f];
}

- (void)bookmarkTapped {
    if (!_pagesReady) return;
    NSInteger curPage = [self currentCenteredPageIndex];
    [_store toggleBookmarkForPage:curPage];
    [self updateBookmarkButtonForPage:curPage];
}

#pragma mark - Navigation Grid, Reader Options & In-PDF Search

- (void)backTapped {
    if (_store && ![_store flushSynchronously]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Annotations Not Saved"
                                                                       message:@"Stay to retry or export an annotated copy. If you leave now, unsaved changes may be lost."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Keep Editing" style:UIAlertActionStyleCancel handler:nil]];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:@"Leave Anyway" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [weakSelf closeReader];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self closeReader];
}

- (void)closeReader {
    _isClosing = YES;
    [_hideTimer invalidate];
    _hideTimer = nil;
    [_trimCancelToken cancel];
    [_searchToken cancel];
    [_exportCancelToken cancel];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)gridTapped {
    if (!_pagesReady) return;
    if (_panelOpen) [self setStylePanelOpen:NO animated:NO];

    NSInteger curPage = [self currentCenteredPageIndex];
    NavigationSheetController *sheet = [[NavigationSheetController alloc] initWithDoc:_doc store:_store currentPage:curPage];
    __weak typeof(self) weakSelf = self;
    sheet.onSelectPage = ^(NSInteger selectedPage) {
        [weakSelf navigateToPage:selectedPage];
    };

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:sheet];
    nav.modalPresentationStyle = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        ? UIModalPresentationFormSheet
        : UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)navigateToPage:(NSInteger)pageIndex {
    if (!_pagesReady) return;
    PDFRecordPageJump(_jumpHistory, [self currentCenteredPageIndex], pageIndex, _pageFrames.count);
    [self jumpToPage:pageIndex animated:NO];
}

- (void)optionsTapped {
    if (!_pagesReady) return;
    if (_panelOpen) [self setStylePanelOpen:NO animated:NO];

    NSString *trimTitle = _autoTrim ? @"✓ Auto-Trim White Margins (On)" : @"Auto-Trim White Margins (Off)";
    NSString *paperTitle = (_theme == PDFReadingThemePaper) ? @"✓ Theme: Crisp Paper" : @"Theme: Crisp Paper";
    NSString *sepiaTitle = (_theme == PDFReadingThemeSepia) ? @"✓ Theme: Warm Sepia" : @"Theme: Warm Sepia";
    NSString *nightTitle = (_theme == PDFReadingThemeNight) ? @"✓ Theme: Night Dark" : @"Theme: Night Dark";

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Reader Options"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    NSUInteger backIndex = PDFJumpBackIndex(_jumpHistory, [self currentCenteredPageIndex]);
    if (backIndex != NSNotFound) {
        NSInteger page = [_jumpHistory[backIndex] integerValue];
        NSArray *remaining = [_jumpHistory subarrayWithRange:NSMakeRange(0, backIndex)];
        NSString *title = [NSString stringWithFormat:@"Jump Back to Page %ld", (long)(page + 1)];
        [ac addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            __strong typeof(self) sSelf = weakSelf;
            if (!sSelf) return;
            [sSelf->_jumpHistory setArray:remaining];
            [sSelf jumpToPage:page animated:NO];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:trimTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf toggleAutoTrim];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:paperTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf applyTheme:PDFReadingThemePaper];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:sepiaTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf applyTheme:PDFReadingThemeSepia];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:nightTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf applyTheme:PDFReadingThemeNight];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Go to Page…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf promptGoToPage];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *pop = ac.popoverPresentationController;
    if (pop) {
        pop.sourceView = _optionsBtn;
        pop.sourceRect = _optionsBtn.bounds;
    }
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)toggleAutoTrim {
    _autoTrim = !_autoTrim;
    [self saveUserPreferences];

    if (_autoTrim && ![_doc hasCachedTrims]) {
        [self beginPreparingDocument];
        return;
    }
    [self layoutPagesPreservingAnchor:YES];
    for (PageView *pv in [_loadedPages allValues]) {
        [pv reloadAnnotationsFromStore];
    }
    [self updateVisiblePagesForceRender:YES];
}

- (void)applyTheme:(PDFReadingTheme)theme {
    if (_theme == theme) return;
    _theme = theme;
    [self saveUserPreferences];
    [self updateCanvasBackground];
    for (PageView *pv in [_loadedPages allValues]) {
        pv.theme = theme;
        [pv reloadAnnotationsFromStore];
    }
    [self updateVisiblePagesForceRender:YES];
}

- (void)promptGoToPage {
    NSInteger cur = [self currentCenteredPageIndex];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Go to Page"
                                                                message:[NSString stringWithFormat:@"Enter page (1 – %ld):", (long)_doc.pageCount]
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.placeholder = [NSString stringWithFormat:@"%ld", (long)(cur + 1)];
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Go" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(self) sSelf = weakSelf;
        if (!sSelf) return;
        NSInteger p = [ac.textFields.firstObject.text integerValue];
        if (p >= 1 && p <= sSelf->_doc.pageCount) {
            [sSelf navigateToPage:(p - 1)];
        }
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - In-PDF Text Search

- (void)searchButtonTapped {
    if (!_pagesReady) return;
    if (_panelOpen) [self setStylePanelOpen:NO animated:NO];

    BOOL show = _searchContainer.hidden;
    _searchContainer.hidden = !show;
    if (show) {
        [_hideTimer invalidate];
        _hideTimer = nil;
        [self layoutHUDChrome];
        [_searchBar becomeFirstResponder];
    } else {
        [_searchToken cancel];
        [_searchBar resignFirstResponder];
        [self resetHideTimer];
    }
}

- (void)closeSearchTapped {
    [_searchToken cancel];
    _searchToken = nil;
    [_searchBar resignFirstResponder];
    _searchContainer.hidden = YES;
    [self resetHideTimer];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self performPDFSearch:searchBar.text];
}

- (void)performPDFSearch:(NSString *)query {
    [_searchToken cancel];
    _searchMatches = @[];
    _currentMatchIndex = -1;

    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        _searchStatusLabel.text = @"";
        return;
    }

    _searchStatusLabel.text = @"Scanning…";
    PDFCancelToken *token = [[PDFCancelToken alloc] init];
    _searchToken = token;
    PDFDoc *doc = _doc;

    __weak typeof(self) weakSelf = self;
    dispatch_async([PDFDoc utilityQueue], ^{
        NSArray<PDFSearchMatch *> *results = [doc searchForQuery:trimmed cancelToken:token progress:^(NSInteger scanned, NSInteger total) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(self) sSelf = weakSelf;
                if (!sSelf || sSelf->_searchToken != token || token.isCancelled) return;
                sSelf->_searchStatusLabel.text = [NSString stringWithFormat:@"%ld/%ld…", (long)scanned, (long)total];
            });
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(self) sSelf = weakSelf;
            if (!sSelf || sSelf->_searchToken != token || token.isCancelled) return;
            sSelf->_searchToken = nil;
            sSelf->_searchMatches = results ?: @[];
            if (sSelf->_searchMatches.count == 0) {
                sSelf->_searchStatusLabel.text = @"0 matches";
            } else {
                sSelf->_currentMatchIndex = 0;
                [sSelf navigateToCurrentSearchMatch];
            }
        });
    });
}

- (void)searchPrevTapped {
    if (_searchMatches.count == 0) return;
    _currentMatchIndex = (_currentMatchIndex - 1 + (NSInteger)_searchMatches.count) % (NSInteger)_searchMatches.count;
    [self navigateToCurrentSearchMatch];
}

- (void)searchNextTapped {
    if (_searchMatches.count == 0) return;
    _currentMatchIndex = (_currentMatchIndex + 1) % (NSInteger)_searchMatches.count;
    [self navigateToCurrentSearchMatch];
}

- (void)navigateToCurrentSearchMatch {
    if (_currentMatchIndex < 0 || (NSUInteger)_currentMatchIndex >= _searchMatches.count) return;
    PDFSearchMatch *m = _searchMatches[(NSUInteger)_currentMatchIndex];
    _searchStatusLabel.text = [NSString stringWithFormat:@"%ld / %lu", (long)(_currentMatchIndex + 1), (unsigned long)_searchMatches.count];
    [self navigateToPage:m.pageIndex];
    PageView *pv = [self ensurePageViewLoadedAtIndex:m.pageIndex];
    [pv pulseHighlightBanner:m.snippet];
}

#pragma mark - PageViewDelegate & Text Notes Editor

- (void)pageViewDidInteract:(PageView *)pageView {
    [self resetHideTimer];
}

- (void)pageViewDidBeginDrawing:(PageView *)pageView {
    if (_panelOpen) {
        [self setStylePanelOpen:NO animated:YES];
    }
}

- (void)pageViewDidChangeAnnotations:(PageView *)pageView {
    [self updateUndoRedoButtons];
}

- (void)pageView:(PageView *)pageView didTapCreateNoteAtNormalizedPoint:(CGPoint)normPt {
    TextNote *note = [[TextNote alloc] init];
    note.normalizedPosition = normPt;
    [self presentNoteEditorForNote:note onPageView:pageView isNew:YES];
}

- (void)pageView:(PageView *)pageView didTapEditNote:(TextNote *)note {
    [self presentNoteEditorForNote:[note copy] onPageView:pageView isNew:NO];
}

- (void)presentNoteEditorForNote:(TextNote *)note onPageView:(PageView *)pageView isNew:(BOOL)isNew {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:(isNew ? @"New Sticky Note" : @"Edit Sticky Note")
                                                                message:[NSString stringWithFormat:@"Page %ld — Drag note cards anytime to reposition.", (long)(pageView.pageIndex + 1)]
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = note.text;
        tf.placeholder = @"Write note…";
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(self) sSelf = weakSelf;
        if (!sSelf) return;
        NSString *txt = [ac.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (txt.length == 0) {
            if (!isNew) {
                [sSelf->_store deleteNoteWithID:note.identifier onPage:pageView.pageIndex];
                [pageView reloadAnnotationsFromStore];
                [sSelf updateUndoRedoButtons];
            }
            return;
        }
        note.text = txt;
        [sSelf->_store saveNote:note onPage:pageView.pageIndex];
        [pageView reloadAnnotationsFromStore];
        [sSelf updateUndoRedoButtons];
    }]];

    if (!isNew) {
        [ac addAction:[UIAlertAction actionWithTitle:@"Switch Note Color" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            __strong typeof(self) sSelf = weakSelf;
            if (!sSelf) return;
            NSString *txt = [ac.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (txt.length > 0) note.text = txt;
            NSArray<UIColor *> *notePalette = @[
                [UIColor colorWithRed:0.98f green:0.84f blue:0.25f alpha:1.0f], // Yellow
                [UIColor colorWithRed:0.58f green:0.88f blue:0.98f alpha:1.0f], // Sky Blue
                [UIColor colorWithRed:0.65f green:0.94f blue:0.68f alpha:1.0f], // Mint Green
                [UIColor colorWithRed:0.99f green:0.68f blue:0.74f alpha:1.0f], // Rose Pink
            ];
            CGFloat r1=0, g1=0, b1=0;
            [note.color getRed:&r1 green:&g1 blue:&b1 alpha:NULL];
            NSUInteger nextIdx = 0;
            for (NSUInteger i = 0; i < notePalette.count; i++) {
                CGFloat r2=0, g2=0, b2=0;
                [notePalette[i] getRed:&r2 green:&g2 blue:&b2 alpha:NULL];
                if (fabs(r1-r2) < 0.08 && fabs(g1-g2) < 0.08) {
                    nextIdx = (i + 1) % notePalette.count;
                    break;
                }
            }
            note.color = notePalette[nextIdx];
            [sSelf->_store saveNote:note onPage:pageView.pageIndex];
            [pageView reloadAnnotationsFromStore];
            [sSelf updateUndoRedoButtons];
        }]];

        [ac addAction:[UIAlertAction actionWithTitle:@"Delete Note" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            __strong typeof(self) sSelf = weakSelf;
            if (!sSelf) return;
            [sSelf->_store deleteNoteWithID:note.identifier onPage:pageView.pageIndex];
            [pageView reloadAnnotationsFromStore];
            [sSelf updateUndoRedoButtons];
        }]];
    }

    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Streaming Vector PDF Export & Share

- (void)shareTapped {
    if (!_pagesReady || _exportCancelToken) return;
    if (_panelOpen) [self setStylePanelOpen:NO animated:NO];
    [_store flushSynchronously];

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Export & Share PDF"
                                                                message:@"Annotated exports keep crisp vector text and blend highlights cleanly."
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Share Annotated PDF…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf runVectorExportAndSaveToLibrary:NO];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Save Annotated Copy to Library" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf runVectorExportAndSaveToLibrary:YES];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Share Original Unmodified PDF…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf presentShareSheetForFileURL:[NSURL fileURLWithPath:self->_pdfPath]];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *pop = ac.popoverPresentationController;
    if (pop) {
        pop.sourceView = _shareBtn;
        pop.sourceRect = _shareBtn.bounds;
    }
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)runVectorExportAndSaveToLibrary:(BOOL)saveToLibrary {
    NSString *baseName = [[_pdfPath lastPathComponent] stringByDeletingPathExtension];
    if (baseName.length == 0) baseName = @"Document";

    NSString *destPath = nil;
    if (saveToLibrary) {
        NSString *dir = [_pdfPath stringByDeletingLastPathComponent];
        NSString *candidate = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-Annotated.pdf", baseName]];
        NSInteger n = 2;
        while ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
            candidate = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-Annotated-%ld.pdf", baseName, (long)n++]];
        }
        destPath = candidate;
    } else {
        destPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-Annotated.pdf", baseName]];
    }

    _loadingOverlay.hidden = NO;
    [_spinner startAnimating];
    _progressBar.hidden = NO;
    _progressBar.progress = 0.0f;
    _loadingLabel.text = @"Exporting vector PDF…";
    _overlayActionBtn.hidden = NO;
    [_overlayActionBtn setTitle:@"Cancel Export" forState:UIControlStateNormal];

    PDFCancelToken *token = [[PDFCancelToken alloc] init];
    _exportCancelToken = token;
    PDFDoc *doc = _doc;
    AnnotationStore *store = _store;

    __weak typeof(self) weakSelf = self;
    dispatch_async([PDFDoc utilityQueue], ^{
        NSError *err = nil;
        BOOL ok = [doc exportAnnotatedPDFToPath:destPath store:store cancelToken:token progress:^(float progress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(self) sSelf = weakSelf;
                if (!sSelf || sSelf->_exportCancelToken != token) return;
                sSelf->_progressBar.progress = progress;
            });
        } error:&err];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(self) sSelf = weakSelf;
            if (!sSelf || sSelf->_isClosing) return;
            sSelf->_exportCancelToken = nil;
            [sSelf->_spinner stopAnimating];
            sSelf->_loadingOverlay.hidden = YES;
            sSelf->_overlayActionBtn.hidden = YES;

            if (!ok) {
                if (!token.isCancelled) {
                    UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Export Failed"
                                                                                      message:(err.localizedDescription ?: @"Could not export PDF.")
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                    [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [sSelf presentViewController:errAlert animated:YES completion:nil];
                }
                return;
            }

            if (saveToLibrary) {
                UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Saved to Library"
                                                                              message:[NSString stringWithFormat:@"Saved \"%@\".", [destPath lastPathComponent]]
                                                                       preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [sSelf presentViewController:done animated:YES completion:nil];
            } else {
                [sSelf presentShareSheetForFileURL:[NSURL fileURLWithPath:destPath]];
            }
        });
    });
}

- (void)presentShareSheetForFileURL:(NSURL *)fileURL {
    if (!fileURL) return;
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ] applicationActivities:nil];
    UIPopoverPresentationController *pop = avc.popoverPresentationController;
    if (pop) {
        pop.sourceView = _shareBtn;
        pop.sourceRect = _shareBtn.bounds;
    }
    [self presentViewController:avc animated:YES completion:nil];
}

@end
