#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "Models.h"
#import "PDFDoc.h"

typedef NS_ENUM(NSInteger, ReaderTool) {
    ReaderToolScroll = 0,
    ReaderToolPen    = 1,
    ReaderToolMarker = 2,
    ReaderToolEraser = 3,
    ReaderToolNote   = 4,
};

@class PageView;

@protocol PageViewDelegate <NSObject>
- (void)pageViewDidInteract:(PageView *)pageView;
- (void)pageViewDidBeginDrawing:(PageView *)pageView;
- (void)pageViewDidChangeAnnotations:(PageView *)pageView;
- (void)pageView:(PageView *)pageView didTapCreateNoteAtNormalizedPoint:(CGPoint)normPt;
- (void)pageView:(PageView *)pageView didTapEditNote:(TextNote *)note;
@end

@interface PageView : UIView

@property (nonatomic, weak) id<PageViewDelegate> delegate;
@property (nonatomic, assign, readonly) NSInteger pageIndex;
@property (nonatomic, assign) CGRect trim;
@property (nonatomic, assign) PDFReadingTheme theme;
@property (nonatomic, assign) ReaderTool tool;
@property (nonatomic, strong) UIColor *drawColor;
@property (nonatomic, assign) CGFloat penWidthFraction;
@property (nonatomic, assign) CGFloat markerWidthFraction;
@property (nonatomic, assign) BOOL snapStraightLines;

- (instancetype)initWithDoc:(PDFDoc *)doc
                      store:(AnnotationStore *)store
                      index:(NSInteger)index
                       trim:(CGRect)trim
                      theme:(PDFReadingTheme)theme;

- (BOOL)hasLoadedBitmap;
- (void)reloadAnnotationsFromStore;
- (void)renderContentWithZoomScale:(CGFloat)zoomScale;
- (void)releaseContent;
- (void)cancelActiveTouchIfNeeded;
- (void)pulseHighlightBanner:(NSString *)bannerText;

@end
