#import <Foundation/Foundation.h>
@protocol ReKeyControl
- (void)lifecycleWithActive:(BOOL)active reply:(void (^)(BOOL))reply;
- (void)requestInputMonitoringWithReply:(void (^)(BOOL))reply;
- (void)reloadWithReply:(void (^)(BOOL))reply;
- (void)statusWithReply:(void (^)(NSString *))reply;
- (void)contextWithApp:(NSString *)app inputSource:(NSString *)source secure:(BOOL)secure accessibility:(BOOL)accessibility reply:(void (^)(BOOL))reply;
- (void)actionsWithReply:(void (^)(NSData *))reply;
- (void)eventsWithEnabled:(BOOL)enabled reply:(void (^)(NSData *))reply;
@end
