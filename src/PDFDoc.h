#import <UIKit/UIKit.h>
#import "Models.h"

typedef NS_ENUM(NSInteger, PDFReadingTheme) {
    PDFReadingThemePaper = 0,
    PDFReadingThemeSepia = 1,
    PDFReadingThemeNight = 2,
};

typedef NS_ENUM(NSInteger, PDFNotebookTemplate) {
    PDFNotebookTemplateBlank   = 0,
    PDFNotebookTemplateRuled   = 1,
    PDFNotebookTemplateGrid    = 2,
    PDFNotebookTemplateDotted  = 3,
    PDFNotebookTemplateCornell = 4,
};

@interface PDFOutlineItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, assign) NSInteger level;
@end

@interface PDFSearchMatch : NSObject
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, copy) NSString *snippet;
@end

@interface PDFCancelToken : NSObject
@property (atomic, assign, getter=isCancelled) BOOL cancelled;
- (void)cancel;
@end

@interface PDFDoc : NSObject

@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, assign, readonly) NSInteger pageCount;
@property (nonatomic, assign, readonly) BOOL isEncrypted;
@property (nonatomic, assign, readonly) BOOL isLocked;

+ (dispatch_queue_t)renderQueue;
+ (dispatch_queue_t)utilityQueue;

- (instancetype)initWithPath:(NSString *)path;
- (BOOL)unlockWithPassword:(NSString *)password;

- (CGSize)pageSizeAtIndex:(NSInteger)index;
- (CGRect)trimAtIndex:(NSInteger)index;
- (CGRect)trimAtIndex:(NSInteger)index autoTrim:(BOOL)autoTrim;

- (BOOL)hasCachedTrims;
- (void)prepareTrimsWithCancelToken:(PDFCancelToken *)token
                           progress:(void (^)(float progress))progressBlock;

- (UIImage *)renderPage:(NSInteger)index
                 region:(CGRect)region
             pixelWidth:(CGFloat)pixelWidth
                  theme:(PDFReadingTheme)theme;

- (UIImage *)renderThumbnailAtIndex:(NSInteger)index
                         maxPixelSide:(CGFloat)maxPixelSide;

// Table of Contents & Text Search
- (NSArray<PDFOutlineItem *> *)outlineItems;
- (NSString *)extractTextForPage:(NSInteger)index;
- (NSArray<PDFSearchMatch *> *)searchForQuery:(NSString *)query
                                  cancelToken:(PDFCancelToken *)token
                                     progress:(void (^)(NSInteger scanned, NSInteger total))progressBlock;

// Vector PDF Export & Notebook Creation
- (BOOL)exportAnnotatedPDFToPath:(NSString *)outputPath
                           store:(AnnotationStore *)store
                     cancelToken:(PDFCancelToken *)token
                        progress:(void (^)(float progress))progressBlock
                           error:(NSError **)outError;

+ (BOOL)createNotebookPDFAtPath:(NSString *)outputPath
                  templateStyle:(PDFNotebookTemplate)style
                      pageCount:(NSInteger)pageCount
                          error:(NSError **)outError;

@end
