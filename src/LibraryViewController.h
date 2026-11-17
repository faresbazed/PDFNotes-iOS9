#import <UIKit/UIKit.h>

@interface LibraryViewController : UIViewController

@property (nonatomic, copy, readonly) NSString *directoryPath;

- (instancetype)initWithDirectory:(NSString *)directoryPath;
- (void)reloadFiles;
- (void)openFileAtPath:(NSString *)pdfPath;

@end
