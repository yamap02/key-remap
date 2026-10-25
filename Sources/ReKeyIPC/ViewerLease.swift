import Foundation

/// The Agent may inspect focused UI elements only while Core has a live
/// EventViewer request. Losing the connection cannot extend this lease.
public struct ViewerLease {
    private var deadline: ContinuousClock.Instant?
    public init() {}
    public mutating func update(requested: Bool, at now: ContinuousClock.Instant = .now) {
        deadline = requested ? now + .milliseconds(500) : nil
    }
    public func allowsFocusInspection(at now: ContinuousClock.Instant = .now) -> Bool {
        deadline.map { now < $0 } ?? false
    }
}
