#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>
@interface Driver : NSObject <SPUUserDriver>
@end
@implementation Driver
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)r reply:(void (^)(SUUpdatePermissionResponse *))reply { exit(91); }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))c {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)i state:(SPUUserUpdateState *)s reply:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceInstall); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)d {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)e {}
- (void)showUpdateNotFoundWithError:(NSError *)e acknowledgement:(void (^)(void))a { printf("NO_UPDATE\n"); exit(92); }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement {
    NSError *underlying = error;
    BOOL rejectedSignature = NO;
    for (int i = 0; underlying && i < 8; ++i) {
        if (underlying.code == SUValidationError &&
            [underlying.domain isEqualToString:SUSparkleErrorDomain] &&
            [underlying.localizedDescription containsString:@"EdDSA signature does not match"]) {
            rejectedSignature = YES;
        }
        underlying = underlying.userInfo[NSUnderlyingErrorKey];
    }
    printf("ERROR %ld SIGNATURE_REJECTED %d\n", (long)error.code, rejectedSignature);
    fflush(stdout);
    exit(rejectedSignature ? 0 : 97);
}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))c {}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)l {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)l {}
- (void)showDownloadDidStartExtractingUpdate {}
- (void)showExtractionReceivedProgress:(double)p { printf("UNEXPECTED_EXTRACTION\n"); exit(98); }
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))r { printf("UNEXPECTED_READY\n"); exit(93); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)t retryTerminatingApplication:(void (^)(void))r { printf("UNEXPECTED_INSTALL\n"); exit(94); }
- (void)showUpdateInstalledAndRelaunched:(BOOL)r acknowledgement:(void (^)(void))a { exit(95); }
- (void)dismissUpdateInstallation {}
@end
int main(void) { @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    Driver *driver = [Driver new];
    SPUUpdater *updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:driver delegate:nil];
    NSError *error = nil;
    if (![updater startUpdater:&error]) { fprintf(stderr,"START %s\n",error.localizedDescription.UTF8String); return 90; }
    [updater checkForUpdates];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC),dispatch_get_main_queue(),^{printf("TIMEOUT\n");exit(96);});
    [app run];
} }
