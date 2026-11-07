import Foundation

// Runs the production recovery state machine against disposable file-backed
// service state. No launchd or installed ReKey service is touched.
@main struct RecoveryFixture {
    @MainActor static func main() async {
        do {
            guard CommandLine.arguments.count == 4 else { exit(64) }
            let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let suite = CommandLine.arguments[2]
            let action = CommandLine.arguments[3]
            guard let defaults = UserDefaults(suiteName: suite) else { exit(65) }
            if action == "cleanup" { defaults.removePersistentDomain(forName: suite); return }
            let recovery = UpdateServiceRecovery(defaults: defaults)
            func file(_ name: String) -> URL { root.appendingPathComponent("service-" + name) }
            func record(_ value: String) throws {
                let url = root.appendingPathComponent("actions")
                let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                try (previous + value + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
            let operations = UpdateServiceRecovery.Operations(
                status: { name in
                    switch try? String(contentsOf: file(name), encoding: .utf8) {
                    case "enabled": .enabled
                    case "notRegistered": .notRegistered
                    default: .unavailable
                    }
                },
                stop: { name in
                    try "notRegistered".write(to: file(name), atomically: true, encoding: .utf8)
                    try record("stop-" + name)
                },
                start: { name in
                    try "enabled".write(to: file(name), atomically: true, encoding: .utf8)
                    try record("start-" + name)
                })
            switch action {
            case "prepare": try await recovery.prepare(build: "100", operations: operations)
            case "recover": try await recovery.recover(build: "101", operations: operations)
            case "cancel": try await recovery.recover(build: "100", operations: operations, allowSameBuild: true)
            case "hold":
                do {
                    try await recovery.recover(build: "100", operations: operations)
                    throw NSError(domain: "RecoveryFixture", code: 1)
                } catch UpdateServiceRecovery.RecoveryError.pendingUpdate {}
            default: exit(64)
            }
        } catch {
            fputs("Recovery fixture failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
