#import "AppDelegate.h"
#import "LibraryViewController.h"
#import "LibraryFiles.h"
#import "Models.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [AnnotationStore migrateLegacyAnnotationKeysIfNeeded];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.library = [[LibraryViewController alloc] init];
    self.nav = [[UINavigationController alloc] initWithRootViewController:self.library];
    self.nav.navigationBar.tintColor = [UIColor colorWithRed:0.14f green:0.48f blue:0.96f alpha:1.0f];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];

    NSURL *launchURL = launchOptions[UIApplicationLaunchOptionsURLKey];
    if ([launchURL isKindOfClass:[NSURL class]]) {
        [self handleIncomingURL:launchURL];
    }
    return YES;
}

// iOS 9.0+ external file handoff
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<NSString *,id> *)options {
    return [self handleIncomingURL:url];
}

// Legacy iOS fallback
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    return [self handleIncomingURL:url];
}

- (BOOL)handleIncomingURL:(NSURL *)url {
    if (!url || !url.isFileURL) return NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return NO;
    NSError *error = nil;
    NSString *finalPath = PDFImportDocument(url.path, [AnnotationStore documentsDirectory], &error);
    if (!finalPath) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Could Not Import PDF"
                                                                       message:error.localizedDescription
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *presenter = self.nav;
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;
        [presenter presentViewController:alert animated:YES completion:nil];
        return NO;
    }

    if (self.nav.presentedViewController) {
        [self.nav dismissViewControllerAnimated:NO completion:nil];
    }
    [self.nav popToRootViewControllerAnimated:NO];
    [self.library reloadFiles];
    [self.library openFileAtPath:finalPath];
    return YES;
}

@end
