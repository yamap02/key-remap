#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>

@interface CancelDriver : NSObject <SPUUserDriver>
@end
@implementation CancelDriver
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)r reply:(void (^)(SUUpdatePermissionResponse *))reply { exit(91); }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))c {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)i state:(SPUUserUpdateState *)s reply:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceInstall); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)d {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)e {}
- (void)showUpdateNotFoundWithError:(NSError *)e acknowledgement:(void (^)(void))a { exit(92); }
- (void)showUpdaterError:(NSError *)e acknowledgement:(void (^)(void))a { fprintf(stderr, "ERROR %s\n", e.localizedDescription.UTF8String); exit(93); }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancel { cancel(); }
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)l {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)l {}
- (void)showDownloadDidStartExtractingUpdate { exit(94); }
- (void)showExtractionReceivedProgress:(double)p { exit(94); }
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))r { exit(95); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)t retryTerminatingApplication:(void (^)(void))r { exit(95); }
- (void)showUpdateInstalledAndRelaunched:(BOOL)r acknowledgement:(void (^)(void))a { exit(95); }
- (void)dismissUpdateInstallation {}
@end

@interface CancelDelegate : NSObject <SPUUpdaterDelegate>
@property BOOL cancelled;
@property BOOL aborted;
@end
@implementation CancelDelegate
- (void)userDidCancelDownload:(SPUUpdater *)updater { self.cancelled = YES; }
- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error { self.aborted = YES; }
- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)check error:(NSError *)error {
    if (self.cancelled && !self.aborted && error == nil) { puts("CANCELLED THEN FINISHED NIL"); fflush(stdout); exit(0); }
    fprintf(stderr, "Unexpected cancellation callbacks: cancelled=%d aborted=%d error=%s\n", self.cancelled, self.aborted, error.description.UTF8String ?: "nil");
    exit(96);
}
@end

int main(void) { @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    CancelDriver *driver = [CancelDriver new];
    CancelDelegate *delegate = [CancelDelegate new];
    SPUUpdater *updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:driver delegate:delegate];
    NSError *error = nil;
    if (![updater startUpdater:&error]) { fprintf(stderr, "START %s\n", error.localizedDescription.UTF8String); return 90; }
    [updater checkForUpdates];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ puts("TIMEOUT"); exit(97); });
    [app run];
} }
