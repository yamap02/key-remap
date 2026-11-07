#import <Foundation/Foundation.h>
extern BOOL SPUSystemNeedsAuthorizationAccessForBundlePath(NSString *bundlePath);
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 64;
        NSString *path = [NSString stringWithUTF8String:argv[1]];
        printf("%s\n", SPUSystemNeedsAuthorizationAccessForBundlePath(path) ? "authorization-required" : "authorization-not-required");
        return 0;
    }
}
