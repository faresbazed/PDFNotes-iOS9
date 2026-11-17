#import <UIKit/UIKit.h>

@class LibraryViewController;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@property (nonatomic, strong) LibraryViewController *library;

@end
