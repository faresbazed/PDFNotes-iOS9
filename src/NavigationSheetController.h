#import <UIKit/UIKit.h>
#import "Models.h"
#import "PDFDoc.h"

@interface NavigationSheetController : UIViewController

@property (nonatomic, copy) void (^onSelectPage)(NSInteger pageIndex);

- (instancetype)initWithDoc:(PDFDoc *)doc
                      store:(AnnotationStore *)store
                currentPage:(NSInteger)currentPage;

@end
