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
        case pendingUpdate
        var errorDescription: String? {
            switch self {
            case .unavailable(let name): return "サービスを利用できません: \(name)"
            case .pendingUpdate: return "更新が保留中です。更新を確認して再開またはキャンセルしてください。"
            }
        }
    }
    private let defaults: UserDefaults
    private let buildKey = "updateRecovery.lastBuild"
    private let pendingKey = "updateRecovery.pendingServices"
    private let originKey = "updateRecovery.pendingOriginBuild"
    private let serviceNames = ["core", "agent"]

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var hasPendingRecovery: Bool { defaults.object(forKey: pendingKey) != nil }

    private func pendingRecord() throws -> (services: [String], origin: String) {
        guard let pending = defaults.stringArray(forKey: pendingKey),
              let origin = defaults.string(forKey: originKey), !origin.isEmpty,
              Set(pending).count == pending.count,
              pending.allSatisfy({ serviceNames.contains($0) }) else {
            throw RecoveryError.unavailable("invalid recovery record")
        }
        return (pending, origin)
    }

    // Persist the exact enabled set before stopping anything. The next app can
    // restore it after an update, a failed stop, or an interrupted process.
    func prepare(build: String, operations: Operations) async throws {
        guard !build.isEmpty else { throw RecoveryError.unavailable("build") }
        guard !hasPendingRecovery else { throw RecoveryError.unavailable("pending recovery") }
        var enabled: [String] = []
        for name in serviceNames {
            switch operations.status(name) {
            case .enabled: enabled.append(name)
            case .notRegistered, .requiresApproval: break
            case .unavailable: throw RecoveryError.unavailable(name)
            }
        }
        defaults.set(build, forKey: originKey)
        defaults.set(enabled, forKey: pendingKey)
        guard defaults.synchronize() else { throw RecoveryError.unavailable("recovery record") }
        try await ensureStopped(operations: operations)
    }

    // A previous process may have died immediately after saving the record,
    // or a service may have been re-enabled externally. Check again before
    // allowing Sparkle to continue, including services originally disabled.
    func ensureStopped(operations: Operations) async throws {
        let pending = try pendingRecord().services
        for name in serviceNames {
            let status = operations.status(name)
            if pending.contains(name) {
                switch status {
                case .enabled: try await operations.stop(name)
                case .notRegistered: break
                case .requiresApproval, .unavailable: throw RecoveryError.unavailable(name)
                }
                guard operations.status(name) == .notRegistered else { throw RecoveryError.unavailable(name) }
            } else {
                switch status {
                case .notRegistered, .requiresApproval: break
                case .enabled, .unavailable: throw RecoveryError.unavailable(name)
                }
            }
        }
    }

    // Quit can trigger an install-on-quit update. This synchronous check
    // never changes registrations or waits for launchd during termination.
    func verifyStopped(operations: Operations) throws {
        let pending = try pendingRecord().services
        for name in serviceNames {
            switch operations.status(name) {
            case .notRegistered: break
            case .requiresApproval where !pending.contains(name): break
            case .enabled, .requiresApproval, .unavailable: throw RecoveryError.unavailable(name)
            }
        }
    }

    func recover(build: String, operations: Operations, allowSameBuild: Bool = false) async throws {
        guard !build.isEmpty else { return }
        let previous = defaults.string(forKey: buildKey)
        var pending: [String]?
        if hasPendingRecovery {
            let record = try pendingRecord()
            if record.origin == build && !allowSameBuild {
                // The previous process may have exited after persisting the
                // intent but before it stopped all services. A staged update
                // can still install on quit, so recheck before reporting the
                // pending state rather than leaving Core running.
                try await ensureStopped(operations: operations)
                throw RecoveryError.pendingUpdate
            }
            pending = record.services
        }
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
            defaults.set(previous, forKey: originKey)
            defaults.set(pending, forKey: pendingKey)
            guard defaults.synchronize() else { throw RecoveryError.unavailable("recovery record") }
        }
        guard let pending else { throw RecoveryError.unavailable("invalid recovery record") }
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
        defaults.removeObject(forKey: originKey)
        defaults.synchronize()
    }
}
