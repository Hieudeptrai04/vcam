#import "VcamAppDelegate.h"
#import "VcamViewController.h"

@implementation VcamAppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    VcamViewController *root = [[VcamViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc]
        initWithRootViewController:root];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
