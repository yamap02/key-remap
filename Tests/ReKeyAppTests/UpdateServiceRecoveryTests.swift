import Foundation
import Testing
import ReKeyModel
@testable import ReKeyApp

@MainActor private final class RecoveryFixture {
    let suite = "rekey-recovery-test.\(UUID().uuidString)"
    let defaults: UserDefaults
    var status: [String: UpdateServiceRecovery.Status] = ["core": .enabled, "agent": .notRegistered]
    var actions: [String] = []
    var failStart = false
    init() { defaults = UserDefaults(suiteName: suite)! }
    func operations() -> UpdateServiceRecovery.Operations {
        .init(status: { self.status[$0] ?? .unavailable },
              stop: { name in self.actions.append("stop-\(name)"); self.status[name] = .notRegistered },
              start: { name in
                  self.actions.append("start-\(name)")
                  if self.failStart { throw NSError(domain: "test", code: 1) }
                  self.status[name] = .enabled
              })
    }
    func clean() { defaults.removePersistentDomain(forName: suite) }
}

@Test @MainActor func updateRecoveryRestartsOnlyPreviouslyEnabledServices() async throws {
    let fixture = RecoveryFixture(); defer { fixture.clean() }
    let recovery = UpdateServiceRecovery(defaults: fixture.defaults)
    try await recovery.recover(build: "10", operations: fixture.operations())
    #expect(fixture.actions.isEmpty)
    try await recovery.recover(build: "10", operations: fixture.operations())
    #expect(fixture.actions.isEmpty)
    try await recovery.recover(build: "11", operations: fixture.operations())
    #expect(fixture.actions == ["stop-core", "start-core"])
    #expect(fixture.status["agent"] == .notRegistered)
    fixture.actions = []
    try await recovery.recover(build: "11", operations: fixture.operations())
    #expect(fixture.actions.isEmpty)
}

@Test @MainActor func updateRecoveryRetriesAfterInterruptedRestart() async throws {
    let fixture = RecoveryFixture(); defer { fixture.clean() }
    let recovery = UpdateServiceRecovery(defaults: fixture.defaults)
    try await recovery.recover(build: "10", operations: fixture.operations())
    fixture.failStart = true
    do {
        try await recovery.recover(build: "11", operations: fixture.operations())
        Issue.record("A failed registration must be reported")
    } catch {}
    #expect(fixture.status["core"] == .notRegistered)
    fixture.failStart = false; fixture.actions = []
    let afterRelaunch = UpdateServiceRecovery(defaults: fixture.defaults)
    try await afterRelaunch.recover(build: "11", operations: fixture.operations())
    #expect(fixture.actions == ["start-core"])
    #expect(fixture.status["core"] == .enabled)
    #expect(fixture.status["agent"] == .notRegistered)
}

@Test @MainActor func updateRecoveryDoesNotOverrideApproval() async throws {
    let fixture = RecoveryFixture(); defer { fixture.clean() }
    let recovery = UpdateServiceRecovery(defaults: fixture.defaults)
    try await recovery.recover(build: "10", operations: fixture.operations())
    fixture.failStart = true
    do { try await recovery.recover(build: "11", operations: fixture.operations()) } catch {}
    fixture.status["core"] = .requiresApproval; fixture.actions = []
    do {
        try await recovery.recover(build: "11", operations: fixture.operations())
        Issue.record("Approval must not be bypassed")
    } catch {}
    #expect(fixture.actions.isEmpty)
}

@Test @MainActor func recoveryLeavesConfigurationIntact() async throws {
    let fixture = RecoveryFixture(); defer { fixture.clean() }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReKey-recovery-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ConfigurationStore(url: root.appendingPathComponent("rekey.json"))
    var config = Configuration()
    config.profiles[0].name = "Preserved"
    config.global.disable_on_quit = false
    try store.save(config)
    let data = try Data(contentsOf: store.url)
    let recovery = UpdateServiceRecovery(defaults: fixture.defaults)
    try await recovery.recover(build: "10", operations: fixture.operations())
    try await recovery.recover(build: "11", operations: fixture.operations())
    let afterRelaunch = ConfigurationStore(url: store.url)
    #expect(try Data(contentsOf: store.url) == data)
    #expect(try afterRelaunch.load().profiles[0].name == "Preserved")
    #expect(try !afterRelaunch.load().global.disable_on_quit)
}

@Test @MainActor func recoveryReportsUnknownServiceState() async throws {
    let fixture = RecoveryFixture(); defer { fixture.clean() }
    let recovery = UpdateServiceRecovery(defaults: fixture.defaults)
    try await recovery.recover(build: "10", operations: fixture.operations())
    fixture.status["core"] = .unavailable
    do {
        try await recovery.recover(build: "11", operations: fixture.operations())
        Issue.record("Unknown service state must not be treated as disabled")
    } catch {}
    #expect(fixture.actions.isEmpty)
    fixture.status["core"] = .enabled
    try await recovery.recover(build: "11", operations: fixture.operations())
    #expect(fixture.actions == ["stop-core", "start-core"])
}

@Test @MainActor func updatePreparationStopsOnlyEnabledServicesAndRestoresAfterRelaunch() async throws {
    let fixture = RecoveryFixture(); defer { fixture.clean() }
    let recovery = UpdateServiceRecovery(defaults: fixture.defaults)
    try await recovery.recover(build: "10", operations: fixture.operations())
    try await recovery.prepare(operations: fixture.operations())
    #expect(fixture.actions == ["stop-core"])
    #expect(recovery.hasPendingRecovery)
    #expect(fixture.status["core"] == .notRegistered)
    fixture.actions = []
    try await UpdateServiceRecovery(defaults: fixture.defaults).recover(build: "11", operations: fixture.operations())
    #expect(fixture.actions == ["start-core"])
    #expect(fixture.status["agent"] == .notRegistered)
    #expect(!recovery.hasPendingRecovery)
}

@Test @MainActor func updatePreparationRetainsRecoveryRecordWhenAStopFails() async throws {
    let fixture = RecoveryFixture(); defer { fixture.clean() }
    fixture.status["agent"] = .enabled
    let recovery = UpdateServiceRecovery(defaults: fixture.defaults)
    try await recovery.recover(build: "10", operations: fixture.operations())
    let normal = fixture.operations()
    let failing = UpdateServiceRecovery.Operations(status: normal.status, stop: { name in
        if name == "agent" { throw NSError(domain: "test", code: 1) }
        try await normal.stop(name)
    }, start: normal.start)
    do { try await recovery.prepare(operations: failing); Issue.record("Stop failure must stop the update") } catch {}
    #expect(recovery.hasPendingRecovery)
    #expect(fixture.status["core"] == .notRegistered)
    #expect(fixture.status["agent"] == .enabled)
    try await recovery.recover(build: "10", operations: fixture.operations())
    #expect(fixture.status["core"] == .enabled)
    #expect(fixture.status["agent"] == .enabled)
    #expect(!recovery.hasPendingRecovery)
}
