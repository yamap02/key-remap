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
    try await recovery.prepare(build: "10", operations: fixture.operations())
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
    do { try await recovery.prepare(build: "10", operations: failing); Issue.record("Stop failure must stop the update") } catch {}
    #expect(recovery.hasPendingRecovery)
    #expect(fixture.status["core"] == .notRegistered)
    #expect(fixture.status["agent"] == .enabled)
    try await recovery.recover(build: "10", operations: fixture.operations(), allowSameBuild: true)
    #expect(fixture.status["core"] == .enabled)
    #expect(fixture.status["agent"] == .enabled)
    #expect(!recovery.hasPendingRecovery)
}

@Test @MainActor func pendingUpdateDoesNotRestartServicesOnOldBuild() async throws {
    let fixture = RecoveryFixture(); defer { fixture.clean() }
    let recovery = UpdateServiceRecovery(defaults: fixture.defaults)
    try await recovery.recover(build: "10", operations: fixture.operations())
    try await recovery.prepare(build: "10", operations: fixture.operations())
    fixture.actions = []
    do {
        try await UpdateServiceRecovery(defaults: fixture.defaults).recover(build: "10", operations: fixture.operations())
        Issue.record("A pending update must not resume services in the old app")
    } catch UpdateServiceRecovery.RecoveryError.pendingUpdate {}
    #expect(fixture.actions.isEmpty)
    #expect(fixture.status["core"] == .notRegistered)
    try await recovery.recover(build: "10", operations: fixture.operations(), allowSameBuild: true)
    #expect(fixture.status["core"] == .enabled)
}

@Test @MainActor func pendingPreparationRechecksServicesAfterInterruptedStop() async throws {
    let fixture = RecoveryFixture(); defer { fixture.clean() }
    let recovery = UpdateServiceRecovery(defaults: fixture.defaults)
    try await recovery.recover(build: "10", operations: fixture.operations())
    let normal = fixture.operations()
    let failing = UpdateServiceRecovery.Operations(status: normal.status, stop: { _ in
        throw NSError(domain: "test", code: 1)
    }, start: normal.start)
    do { try await recovery.prepare(build: "10", operations: failing); Issue.record("Stop failure must be reported") } catch {}
    #expect(fixture.status["core"] == .enabled)
    #expect(recovery.hasPendingRecovery)
    try await recovery.ensureStopped(operations: fixture.operations())
    #expect(fixture.status["core"] == .notRegistered)
    fixture.status["agent"] = .enabled // An external change must fail closed.
    do { try await recovery.ensureStopped(operations: fixture.operations()); Issue.record("Unexpected service must block update") } catch {}
}

@Test @MainActor func oldBuildStopsServicesBeforeReportingInterruptedUpdate() async throws {
    let fixture = RecoveryFixture(); defer { fixture.clean() }
    let recovery = UpdateServiceRecovery(defaults: fixture.defaults)
    let normal = fixture.operations()
    let interrupted = UpdateServiceRecovery.Operations(status: normal.status, stop: { _ in
        throw NSError(domain: "test", code: 1)
    }, start: normal.start)
    do { try await recovery.prepare(build: "10", operations: interrupted); Issue.record("Stop must fail") } catch {}
    #expect(recovery.hasPendingRecovery)
    #expect(fixture.status["core"] == .enabled)
    fixture.actions = []
    do {
        try await UpdateServiceRecovery(defaults: fixture.defaults).recover(build: "10", operations: normal)
        Issue.record("The old build must remain in the pending state")
    } catch UpdateServiceRecovery.RecoveryError.pendingUpdate {}
    #expect(fixture.actions == ["stop-core"])
    #expect(fixture.status["core"] == .notRegistered)
    #expect(recovery.hasPendingRecovery)
}

@Test @MainActor func appBlocksTerminationUntilInterruptedServicesAreStoppedOrRestored() async throws {
    let fixture = RecoveryFixture(); defer { fixture.clean(); TerminationGate.updateServiceOperationInProgress = false }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReKey-update-state-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let recovery = UpdateServiceRecovery(defaults: fixture.defaults)
    let normal = fixture.operations()
    var stopFails = true
    let operations = UpdateServiceRecovery.Operations(status: normal.status, stop: { name in
        if stopFails { throw NSError(domain: "test", code: 1) }
        try await normal.stop(name)
    }, start: normal.start)
    let state = AppState(store: ConfigurationStore(url: root.appendingPathComponent("rekey.json")),
                         startMonitoring: false, updateRecovery: recovery,
                         updateOperations: operations, buildOverride: "10")
    do { try await state.prepareServicesForUpdate(); Issue.record("A failed stop must fail preparation") } catch {}
    #expect(state.updatePrepared)
    #expect(state.unsafePendingUpdate)
    #expect(TerminationGate.updateServiceOperationInProgress)
    #expect(fixture.status["core"] == .enabled)
    #expect(!(await state.recoverServicesAfterUpdate()))
    #expect(state.unsafePendingUpdate)
    #expect(TerminationGate.updateServiceOperationInProgress)

    stopFails = false
    #expect(!(await state.recoverServicesAfterUpdate())) // Still pending, but now safely stopped.
    #expect(state.updatePrepared)
    #expect(!state.unsafePendingUpdate)
    #expect(!TerminationGate.updateServiceOperationInProgress)
    #expect(fixture.status["core"] == .notRegistered)
    #expect(await state.recoverServicesAfterUpdate(allowSameBuild: true))
    #expect(!state.updatePrepared)
    #expect(!state.unsafePendingUpdate)
    #expect(!TerminationGate.updateServiceOperationInProgress)
    #expect(fixture.status["core"] == .enabled)
}

@Test @MainActor func malformedPendingRecoveryFailsClosed() async throws {
    let fixture = RecoveryFixture(); defer { fixture.clean() }
    fixture.defaults.set("invalid", forKey: "updateRecovery.pendingServices")
    do {
        try await UpdateServiceRecovery(defaults: fixture.defaults).recover(build: "10", operations: fixture.operations())
        Issue.record("A malformed pending record must not be ignored")
    } catch {}
    #expect(fixture.actions.isEmpty)
}

@Test @MainActor func missingOriginOrDuplicateServicesNeverResumeInput() async throws {
    for (origin, services) in [(nil, ["core"]), ("", ["core"]), ("10", ["core", "core"])] as [(String?, [String])] {
        let fixture = RecoveryFixture(); defer { fixture.clean() }
        fixture.status["core"] = .notRegistered
        fixture.defaults.set(services, forKey: "updateRecovery.pendingServices")
        if let origin { fixture.defaults.set(origin, forKey: "updateRecovery.pendingOriginBuild") }
        let recovery = UpdateServiceRecovery(defaults: fixture.defaults)
        do {
            try await recovery.recover(build: "10", operations: fixture.operations(), allowSameBuild: true)
            Issue.record("An incomplete recovery record must not restart input")
        } catch {}
        do {
            try await recovery.ensureStopped(operations: fixture.operations())
            Issue.record("An incomplete recovery record must not allow an update")
        } catch {}
        #expect(fixture.actions.isEmpty)
        #expect(recovery.hasPendingRecovery)
    }
}
