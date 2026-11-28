#import <Foundation/Foundation.h>
#import "PDFRasterSize.h"
#include <assert.h>
#include <float.h>

static void checkRasterSizes(void) {
    PDFRasterSize fit = PDFRasterFit(612, 792, 1464, PDFPageMaxSide, PDFPageMaxPixels);
    assert(fit.width == 1464 && fit.height == 1894); // Ordinary fit-to-width is unchanged.
    for (int e = -90; e <= 90; e++) {
        double h = ldexp(612, e);
        for (int w = 100; w <= 4100; w += 200) {
            fit = PDFRasterFit(612, h, w, PDFPageMaxSide, PDFPageMaxPixels);
            assert(fit.width > 0 && fit.width <= PDFPageMaxSide);
            assert(fit.height > 0 && fit.height <= PDFPageMaxSide);
            assert(fit.width * fit.height <= PDFPageMaxPixels);
        }
        fit = PDFRasterFit(612, h, 120, 120, PDFPageMaxPixels);
        assert(MAX(fit.width, fit.height) == 120);
        fit = PDFTrimSampleSize(612, h);
        assert(fit.width <= 200 && fit.height <= 512);
    }
    fit = PDFTrimSampleSize(200, 1024);
    assert(fit.width == 100 && fit.height == 512);
    fit = PDFTrimSampleSize(2, FLT_MAX);
    assert(fit.width == 1 && fit.height == 512);
    assert(!PDFTrimSampleSize(INFINITY, 30).width && !PDFTrimSampleSize(NAN, 30).height);
    assert(!PDFTrimSampleSize(30, 0).width && !PDFTrimSampleSize(-1, 30).width);
}

#define CGRect NSRect
#define CGRectValue rectValue
#define CGRectGetMinY NSMinY
#define CGRectGetMaxY NSMaxY
#define CGRectIntersectsRect NSIntersectsRect
#define CGRectInset NSInsetRect
#define CGRectNull NSZeroRect
#define UIControlStateNormal 0

@interface PageView : NSObject { @public NSRect frame; }
- (NSRect)frame;
@end
@implementation PageView
- (NSRect)frame { return frame; }
- (BOOL)hasLoadedBitmap { return NO; }
- (void)renderContentWithZoomScale:(CGFloat)zoom {}
- (void)releaseContent {}
- (void)removeFromSuperview {}
@end

@interface FakeUI : NSObject {
    BOOL _dragging, _decelerating, _zooming;
    NSInteger _lastPageIndex;
}
@property BOOL dragging, decelerating, zooming;
@property NSInteger lastPageIndex;
@end
@implementation FakeUI
@synthesize dragging = _dragging, decelerating = _decelerating, zooming = _zooming, lastPageIndex = _lastPageIndex;
- (CGFloat)zoomScale { return 1; }
- (NSInteger)pageCount { return 6; }
- (void)setTitle:(NSString *)title forState:(int)state {}
@end

@interface ReaderHarness : NSObject {
@public
    BOOL _pagesReady;
    NSInteger _displayedPageIndex, hudUpdates;
    FakeUI *_scrollView, *_store, *_pagePillBtn, *_doc;
    NSMutableArray *_pageFrames, *requests;
    NSMutableDictionary *_loadedPages;
    NSRect viewport;
}
@end
@implementation ReaderHarness
- (instancetype)init {
    if ((self = [super init])) {
        _pagesReady = YES;
        _displayedPageIndex = NSNotFound;
        _scrollView = _store = _pagePillBtn = _doc = [FakeUI new];
        requests = [NSMutableArray new];
        _loadedPages = [NSMutableDictionary new];
        _pageFrames = [NSMutableArray new];
        for (int i = 0; i < 6; i++) {
            [_pageFrames addObject:[NSValue valueWithRect:NSMakeRect(0, i * 210, 100, 200)]];
        }
        viewport = NSMakeRect(0, 480, 100, 220); // Pages 2 and 3 are visible.
    }
    return self;
}
- (NSRect)currentViewportInContentCoords { return viewport; }
- (NSInteger)currentCenteredPageIndex { return NSMidY(viewport) / 210; }
- (PageView *)ensurePageViewLoadedAtIndex:(NSInteger)i {
    [requests addObject:@(i)];
    PageView *p = [_loadedPages objectForKey:@(i)];
    if (!p) {
        p = [PageView new];
        p->frame = [[_pageFrames objectAtIndex:i] rectValue];
        [_loadedPages setObject:p forKey:@(i)];
        [p release];
    }
    return p;
}
- (void)updatePagePillFrame { hudUpdates++; }
- (void)updateBookmarkButtonForPage:(NSInteger)i {}
#include "window.inc"
@end

int main(void) {
    @autoreleasepool {
        checkRasterSizes();
        ReaderHarness *r = [ReaderHarness new];
        [r updateVisiblePagesForceRender:NO];
        assert(([r->requests isEqual:@[@2, @3, @1, @4]])); // Visible before either neighbor.
        for (int motion = 0; motion < 3; motion++) {
            r->_scrollView.dragging = motion == 0;
            r->_scrollView.decelerating = motion == 1;
            r->_scrollView.zooming = motion == 2;
            [r->requests removeAllObjects];
            [r updateVisiblePagesForceRender:NO];
            assert(([r->requests isEqual:@[@2, @3]]));
        }
        assert(r->hudUpdates == 1);
        r->viewport = NSMakeRect(0, 1050, 100, 180);
        [r updateVisiblePagesForceRender:NO];
        assert(![r->_loadedPages objectForKey:@1] && r->_store.lastPageIndex == 5);
        assert(r->hudUpdates == 2);
        puts("Reader raster limits, visible-first scheduling, HUD and eviction passed.");
    }
    return 0;
}
