#import "AppDelegate.h"
#import "LibraryViewController.h"
#import "Models.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
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
    NSString *srcPath = [url.path stringByResolvingSymlinksInPath] ?: url.path;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:srcPath]) return NO;

    NSString *docs = [AnnotationStore documentsDirectory];
    NSString *inbox = [docs stringByAppendingPathComponent:@"Inbox"];
    NSString *docsPrefix = [docs hasSuffix:@"/"] ? docs : [docs stringByAppendingString:@"/"];
    NSString *inboxPrefix = [inbox hasSuffix:@"/"] ? inbox : [inbox stringByAppendingString:@"/"];

    NSString *finalPath = srcPath;

    // Copy/move into Documents if coming from Inbox or outside Documents
    if (![srcPath hasPrefix:docsPrefix] || [srcPath hasPrefix:inboxPrefix]) {
        NSString *filename = [srcPath lastPathComponent];
        if (filename.length == 0) filename = @"Imported.pdf";
        NSString *base = [filename stringByDeletingPathExtension];
        NSString *ext = [filename pathExtension];
        if (ext.length == 0) ext = @"pdf";

        NSString *dest = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", base, ext]];
        NSInteger n = 2;
        while ([fm fileExistsAtPath:dest]) {
            dest = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%ld.%@", base, (long)n++, ext]];
        }

        NSError *err = nil;
        if ([srcPath hasPrefix:inboxPrefix]) {
            if (![fm moveItemAtPath:srcPath toPath:dest error:&err]) {
                [fm copyItemAtPath:srcPath toPath:dest error:NULL];
                [fm removeItemAtPath:srcPath error:NULL];
            }
        } else {
            [fm copyItemAtPath:srcPath toPath:dest error:&err];
        }

        if ([fm fileExistsAtPath:dest]) {
            finalPath = dest;
        }
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
