#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>
static NSString *base(void) { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"FixtureState"]; }
static BOOL cancelMode(void) { return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"FixtureMode"] isEqualToString:@"cancel"]; }
static BOOL invalidMode(void) { return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"FixtureMode"] isEqualToString:@"invalid"]; }
static BOOL networkMode(void) { return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"FixtureMode"] isEqualToString:@"network"]; }
static BOOL crashMode(void) { return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"FixtureMode"] isEqualToString:@"crash"]; }
static void writeMarker(NSString *filename, NSString *value) { [value writeToFile:[base() stringByAppendingPathComponent:filename] atomically:YES encoding:NSUTF8StringEncoding error:NULL]; }
static BOOL recover(NSString *action) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:[NSBundle.mainBundle objectForInfoDictionaryKey:@"FixtureHelper"]];
    task.arguments = @[base(), [NSBundle.mainBundle objectForInfoDictionaryKey:@"FixtureSuite"], action];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) { writeMarker(@"error", error.description); return NO; }
    [task waitUntilExit];
    if (task.terminationStatus != 0) { writeMarker(@"error", [NSString stringWithFormat:@"recovery %@ failed", action]); return NO; }
    return YES;
}
@interface Driver : NSObject <SPUUserDriver> @end
@implementation Driver
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)r reply:(void (^)(SUUpdatePermissionResponse *))reply { writeMarker(@"error",@"permission prompt"); exit(91); }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))c {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)i state:(SPUUserUpdateState *)s reply:(void (^)(SPUUserUpdateChoice))reply { if (!recover(@"prepare")) exit(98); reply(SPUUserUpdateChoiceInstall); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)d {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)e {}
- (void)showUpdateNotFoundWithError:(NSError *)e acknowledgement:(void (^)(void))a { writeMarker(@"error",e.description); exit(92); }
- (void)showUpdaterError:(NSError *)e acknowledgement:(void (^)(void))a {
    if (!invalidMode() && !networkMode()) { writeMarker(@"error",e.description); exit(93); }
    BOOL rejected = NO;
    NSError *current = e;
    for (int depth = 0; current != nil && depth < 8; ++depth, current = current.userInfo[NSUnderlyingErrorKey]) {
        if (invalidMode() && [current.domain isEqualToString:SUSparkleErrorDomain] && current.code == SUValidationError && [current.localizedDescription containsString:@"EdDSA signature does not match"]) { rejected = YES; break; }
        if (networkMode() && [current.domain isEqualToString:SUSparkleErrorDomain] && current.code == SUDownloadError) { rejected = YES; break; }
    }
    if (!rejected) { writeMarker(@"error", e.description); exit(93); }
    a();
}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))c { if (crashMode()) _exit(70); if (cancelMode()) c(); }
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)l {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)l {}
- (void)showDownloadDidStartExtractingUpdate {}
- (void)showExtractionReceivedProgress:(double)p {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))r { r(SPUUserUpdateChoiceInstall); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)t retryTerminatingApplication:(void (^)(void))r {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)r acknowledgement:(void (^)(void))a { a(); }
- (void)dismissUpdateInstallation {}
@end
@interface Delegate : NSObject <SPUUpdaterDelegate>
@property BOOL cancelled;
@property BOOL aborted;
@end
@implementation Delegate
- (void)userDidCancelDownload:(SPUUpdater *)updater { self.cancelled = YES; }
- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error { self.aborted = YES; }
- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)check error:(NSError *)error {
    if (invalidMode() || networkMode()) {
        if (!self.aborted || error == nil || !recover(@"cancel")) { writeMarker(@"error", @"invalid update recovery failed"); exit(99); }
        writeMarker(networkMode() ? @"network-recovered" : @"invalid-recovered", @"restored");
        exit(0);
    }
    if (!cancelMode()) return;
    if (!self.cancelled || error != nil || !recover(@"cancel")) { writeMarker(@"error", @"cancel recovery failed"); exit(99); }
    writeMarker(@"cancelled", @"restored");
    exit(0);
}
@end
int main(void) { @autoreleasepool {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    if ([version isEqualToString:@"101"]) { if (!recover(@"recover")) return 98; NSError *err = nil; NSString *text = [NSString stringWithContentsOfFile:[base() stringByAppendingPathComponent:@"config"] encoding:NSUTF8StringEncoding error:&err]; writeMarker(@"new-version",text ?: @"missing"); return 0; }
    NSApplication *app = [NSApplication sharedApplication];
    Driver *driver = [Driver new];
    Delegate *delegate = [Delegate new];
    SPUUpdater *updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:driver delegate:delegate];
    NSError *error = nil;
    if (![updater startUpdater:&error]) { writeMarker(@"error",error.description); return 90; }
    [updater checkForUpdates];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_SEC),dispatch_get_main_queue(),^{writeMarker(@"error",@"timeout");exit(96);});
    [app run];
} }
