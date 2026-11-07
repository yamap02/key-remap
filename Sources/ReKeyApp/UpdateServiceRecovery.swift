import Foundation

// Records intent before stopping anything so an interrupted recovery can be
// retried by the next UI process. This does not alter the user's config file.
@MainActor final class UpdateServiceRecovery {
    enum Status { case enabled, notRegistered, requiresApproval, unavailable }
    struct Operations {
        let status: (String) -> Status
        let stop: (String) async throws -> Void
        let start: (String) throws -> Void
    }
    enum RecoveryError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? { if case let .unavailable(name) = self { return "サービスを利用できません: \(name)" }; return nil }
    }
    private let defaults: UserDefaults
    private let buildKey = "updateRecovery.lastBuild"
    private let pendingKey = "updateRecovery.pendingServices"
    private let serviceNames = ["core", "agent"]

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var hasPendingRecovery: Bool { defaults.object(forKey: pendingKey) != nil }

    // Persist the exact enabled set before stopping anything. The next app can
    // restore it after an update, a failed stop, or an interrupted process.
    func prepare(operations: Operations) async throws {
        guard !hasPendingRecovery else { throw RecoveryError.unavailable("pending recovery") }
        var enabled: [String] = []
        for name in serviceNames {
            switch operations.status(name) {
            case .enabled: enabled.append(name)
            case .notRegistered, .requiresApproval: break
            case .unavailable: throw RecoveryError.unavailable(name)
            }
        }
        defaults.set(enabled, forKey: pendingKey)
        guard defaults.synchronize() else { throw RecoveryError.unavailable("recovery record") }
        for name in enabled {
            try await operations.stop(name)
            guard operations.status(name) == .notRegistered else { throw RecoveryError.unavailable(name) }
        }
    }

    func recover(build: String, operations: Operations) async throws {
        guard !build.isEmpty else { return }
        let previous = defaults.string(forKey: buildKey)
        var pending = defaults.stringArray(forKey: pendingKey)
        if pending == nil {
            guard let previous else { defaults.set(build, forKey: buildKey); return }
            guard previous != build else { return }
            var enabled: [String] = []
            for name in serviceNames {
                switch operations.status(name) {
                case .enabled: enabled.append(name)
                case .notRegistered, .requiresApproval: break
                case .unavailable: throw RecoveryError.unavailable(name)
                }
            }
            pending = enabled
            // Commit even an empty list before proceeding: only previously
            // enabled services may be re-enabled after a crash.
            defaults.set(pending, forKey: pendingKey)
            guard defaults.synchronize() else { throw RecoveryError.unavailable("recovery record") }
        }
        guard let pending, pending.allSatisfy({ serviceNames.contains($0) }) else {
            throw RecoveryError.unavailable("invalid recovery record")
        }
        for name in pending {
            switch operations.status(name) {
            case .enabled: try await operations.stop(name)
            case .notRegistered: break // A previous attempt stopped it already.
            case .requiresApproval, .unavailable: throw RecoveryError.unavailable(name)
            }
            try operations.start(name)
            guard operations.status(name) == .enabled else { throw RecoveryError.unavailable(name) }
        }
        defaults.set(build, forKey: buildKey)
        defaults.removeObject(forKey: pendingKey)
        defaults.synchronize()
    }
}
