import Foundation

@objc(ReKeyControl) public protocol ReKeyControl {
    @objc(lifecycleWithActive:reply:) func lifecycle(active: Bool, reply: @escaping @Sendable (Bool) -> Void)
    @objc(reloadWithReply:) func reload(reply: @escaping @Sendable (Bool) -> Void)
    @objc(statusWithReply:) func status(reply: @escaping @Sendable (String) -> Void)
    @objc(contextWithApp:inputSource:secure:accessibility:reply:) func context(app: String, inputSource: String, secure: Bool, accessibility: Bool, reply: @escaping @Sendable (Bool) -> Void)
    @objc(actionsWithReply:) func actions(reply: @escaping @Sendable (Data) -> Void)
    @objc(eventsWithEnabled:reply:) func events(enabled: Bool, reply: @escaping @Sendable (Data) -> Void)
}
