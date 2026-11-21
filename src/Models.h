#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, StrokeKind) {
    StrokeKindPen    = 0,
    StrokeKindMarker = 1,
};

@interface Stroke : NSObject <NSCopying>

@property (nonatomic, assign) StrokeKind kind;
@property (nonatomic, strong) NSMutableArray<NSValue *> *points; // Full-page normalized [0..1] top-left coords
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) CGFloat widthFraction; // Fraction of full untrimmed page width

- (CGFloat)alpha;
- (CGRect)normalizedBounds;
- (void)invalidateBounds;
- (void)addNormalizedPoint:(CGPoint)pt;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
- (UIBezierPath *)pathWithPointMap:(CGPoint (^)(CGPoint))pointMap;

@end

@interface TextNote : NSObject <NSCopying>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, assign) CGPoint normalizedPosition; // Full-page normalized [0..1] top-left coords
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) CGFloat fontSize;

- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;

@end

@interface AnnotationStore : NSObject

@property (nonatomic, copy, readonly) NSString *pdfPath;
@property (nonatomic, copy, readonly) NSString *annotationKey;
@property (nonatomic, assign) NSInteger lastPageIndex;

- (instancetype)initWithPDFPath:(NSString *)pdfPath;

// Strokes
- (NSArray<Stroke *> *)strokesForPage:(NSInteger)pageIndex;
- (BOOL)hasAnnotationsOnPage:(NSInteger)pageIndex;
- (NSUInteger)annotatedPageCount;
- (void)addStroke:(Stroke *)stroke onPage:(NSInteger)pageIndex;
- (void)replaceStrokes:(NSArray<Stroke *> *)strokes onPage:(NSInteger)pageIndex;
- (void)clearPage:(NSInteger)pageIndex;

// Text Notes
- (NSArray<TextNote *> *)notesForPage:(NSInteger)pageIndex;
- (void)saveNote:(TextNote *)note onPage:(NSInteger)pageIndex;
- (void)deleteNoteWithID:(NSString *)noteID onPage:(NSInteger)pageIndex;
- (void)moveNoteWithID:(NSString *)noteID toNormalizedPosition:(CGPoint)pos onPage:(NSInteger)pageIndex recordUndo:(BOOL)recordUndo;

// Bookmarks
- (BOOL)isPageBookmarked:(NSInteger)pageIndex;
- (BOOL)toggleBookmarkForPage:(NSInteger)pageIndex;
- (NSIndexSet *)bookmarkedPages;
- (NSIndexSet *)annotatedPages;

// Multi-step Undo / Redo (covers Pen, Marker, Eraser, Clear Page, and Text Notes)
- (BOOL)canUndo;
- (BOOL)canRedo;
- (NSInteger)undoReturningPage; // Returns affected pageIndex, or NSNotFound
- (NSInteger)redoReturningPage; // Returns affected pageIndex, or NSNotFound

// Persistence
- (void)markDirty;
- (void)flushSynchronously;

// Library file management helpers
+ (NSString *)documentsDirectory;
+ (NSString *)annotationKeyForPDFPath:(NSString *)pdfPath;
+ (void)migrateLegacyAnnotationKeysIfNeeded;
+ (NSString *)annotationFilePathForPDFPath:(NSString *)pdfPath;
+ (BOOL)hasSavedAnnotationsForPDFPath:(NSString *)pdfPath;
+ (NSInteger)savedLastPageForPDFPath:(NSString *)pdfPath;
+ (void)deleteAnnotationsForPath:(NSString *)itemPath isDirectory:(BOOL)isDirectory;
+ (void)moveAnnotationsFromPath:(NSString *)oldPath toPath:(NSString *)newPath isDirectory:(BOOL)isDirectory;

@end

@interface PDFWeakTimerTarget : NSObject
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti
                                     target:(id)target
                                   selector:(SEL)selector
                                    repeats:(BOOL)repeats;
@end
