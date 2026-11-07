#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>
static NSString *base(void) { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"FixtureState"]; }
static void writeMarker(NSString *filename, NSString *value) { [value writeToFile:[base() stringByAppendingPathComponent:filename] atomically:YES encoding:NSUTF8StringEncoding error:NULL]; }
@interface Driver : NSObject <SPUUserDriver> @end
@implementation Driver
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)r reply:(void (^)(SUUpdatePermissionResponse *))reply { writeMarker(@"error",@"permission prompt"); exit(91); }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))c {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)i state:(SPUUserUpdateState *)s reply:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceInstall); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)d {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)e {}
- (void)showUpdateNotFoundWithError:(NSError *)e acknowledgement:(void (^)(void))a { writeMarker(@"error",e.description); exit(92); }
- (void)showUpdaterError:(NSError *)e acknowledgement:(void (^)(void))a { writeMarker(@"error",e.description); exit(93); }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))c {}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)l {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)l {}
- (void)showDownloadDidStartExtractingUpdate {}
- (void)showExtractionReceivedProgress:(double)p {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))r { r(SPUUserUpdateChoiceInstall); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)t retryTerminatingApplication:(void (^)(void))r {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)r acknowledgement:(void (^)(void))a { a(); }
- (void)dismissUpdateInstallation {}
@end
int main(void) { @autoreleasepool {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    if ([version isEqualToString:@"101"]) { NSError *err = nil; NSString *text = [NSString stringWithContentsOfFile:[base() stringByAppendingPathComponent:@"config"] encoding:NSUTF8StringEncoding error:&err]; writeMarker(@"new-version",text ?: @"missing"); return 0; }
    NSApplication *app = [NSApplication sharedApplication];
    Driver *driver = [Driver new];
    SPUUpdater *updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:driver delegate:nil];
    NSError *error = nil;
    if (![updater startUpdater:&error]) { writeMarker(@"error",error.description); return 90; }
    [updater checkForUpdates];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_SEC),dispatch_get_main_queue(),^{writeMarker(@"error",@"timeout");exit(96);});
    [app run];
} }
