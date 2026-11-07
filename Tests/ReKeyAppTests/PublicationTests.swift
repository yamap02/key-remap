import Testing
import Foundation
import Combine
import ReKeyModel
@testable import ReKeyApp

private func readyStatus() -> RuntimeStatus {
    RuntimeStatus(paused: false, driver_ready: true, agent_accessibility: true,
                  input_monitoring: true, seized_devices: 1, conflict: false, error: "", uid: 501)
}

private func event(_ index: Int) -> TraceEvent {
    TraceEvent(time_ns: UInt64(index), device: 0, input: 4, input_down: true,
               output: 5, output_down: true, input_modifiers: 0, output_modifiers: 0, rule: -1)
}

@Test @MainActor func publishedBindingsStillSaveNestedEdits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(url: directory.appendingPathComponent("rekey.json"))
    let state = AppState(store: store, startMonitoring: false)
    var changes = 0
    let subscription = state.objectWillChange.sink { changes += 1 }
    state.simpleMappings = [.init(from: "caps_lock", to: "left_control")]
    state.config.global.thresholds_ms.alone = 250
    state.changed()
    state.flush()
    let persisted = try store.load()
    #expect(persisted.activeProfile.simple.first?.from.key == "caps_lock")
    #expect(persisted.activeProfile.simple.first?.to.first?.key == "left_control")
    #expect(persisted.global.thresholds_ms.alone == 250)
    #expect(changes > 0)
    #expect(state.saveStatus == "保存済み")
    withExtendedLifetime(subscription) {}
}

@Test @MainActor func updatePreparationRequiresSuccessfulSettingsSave() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = ConfigurationStore(url: directory.appendingPathComponent("rekey.json"))
    let state = AppState(store: store, startMonitoring: false)
    state.config.profiles[0].name = "Update preserves this"
    state.changed()
    try state.saveBeforeUpdate()
    #expect(try store.load().profiles[0].name == "Update preserves this")

    // A clean editor must still reject an I/O failure: dirty == false does
    // not prove the attempted save succeeded.
    let blocked = directory.appendingPathComponent("not-a-directory")
    try Data("file".utf8).write(to: blocked)
    let broken = AppState(store: ConfigurationStore(url: blocked.appendingPathComponent("rekey.json")), startMonitoring: false)
    #expect(throws: (any Error).self) { try broken.saveBeforeUpdate() }
    #expect(broken.saveStatus == "保存エラー")
}

@Test @MainActor func unchangedHeartbeatsDoNotInvalidateSettings() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("rekey.json")
    let runtime = RuntimeClient()
    let state = AppState(store: ConfigurationStore(url: url), runtime: runtime, startMonitoring: false)
    var changes = 0
    let subscription = state.objectWillChange.sink { changes += 1 }
    let ready = readyStatus()
    runtime.updateStatus(ready)
    #expect(changes == 1)
    #expect(state.operational)
    for _ in 0..<50_000 { runtime.updateStatus(ready) }
    #expect(changes == 1)
    var paused = ready
    paused.paused = true
    runtime.updateStatus(paused)
    #expect(changes == 2)
    #expect(state.isPaused)
    #expect(!state.operational)
    withExtendedLifetime(subscription) {}
}

@Test @MainActor func eventUpdatesAreBoundedAndIsolatedFromSettings() {
    let runtime = RuntimeClient()
    runtime.updateStatus(readyStatus())
    runtime.startViewer()
    var runtimeChanges = 0
    var logChanges = 0
    let runtimeSubscription = runtime.objectWillChange.sink { runtimeChanges += 1 }
    let logSubscription = runtime.eventLog.objectWillChange.sink { logChanges += 1 }
    runtime.receiveEvents([], session: runtime.viewerSession)
    #expect(logChanges == 0)
    runtime.receiveEvents((0..<5_000).map(event), session: runtime.viewerSession)
    #expect(runtime.eventLog.events.count == 2_000)
    #expect(runtime.eventLog.events.first?.time_ns == 3_000)
    runtime.receiveEvents((5_000..<5_010).map(event), session: runtime.viewerSession)
    #expect(runtime.eventLog.events.count == 2_000)
    #expect(runtime.eventLog.events.first?.time_ns == 3_010)
    #expect(runtime.eventLog.events.last?.time_ns == 5_009)
    #expect(logChanges == 2)
    #expect(runtimeChanges == 0)
    runtime.eventLog.clear()
    #expect(runtime.eventLog.events.isEmpty)
    runtime.eventLog.clear()
    #expect(logChanges == 3)
    withExtendedLifetime((runtimeSubscription, logSubscription)) {}
}

@Test @MainActor func closedOrSuspendedViewerRejectsDelayedReplies() {
    let runtime = RuntimeClient()
    runtime.updateStatus(readyStatus())
    runtime.startViewer()
    let oldSession = runtime.viewerSession
    runtime.stopViewer()
    runtime.startViewer()
    runtime.receiveEvents([event(0)], session: oldSession)
    #expect(runtime.eventLog.events.isEmpty)
    let activeSession = runtime.viewerSession
    runtime.receiveEvents([event(1)], session: activeSession)
    #expect(runtime.eventLog.events.count == 1)
    runtime.suspendViewer()
    runtime.receiveEvents([event(2)], session: activeSession)
    #expect(runtime.eventLog.events.isEmpty)
}

@Test @MainActor func permissionOrHeartbeatLossImmediatelyClearsEvents() {
    let runtime = RuntimeClient()
    for loss in 0..<3 {
        runtime.updateStatus(readyStatus())
        runtime.startViewer()
        runtime.receiveEvents([event(0)], session: runtime.viewerSession)
        #expect(runtime.eventLog.events.count == 1)
        var denied = readyStatus()
        if loss == 0 { denied.input_monitoring = false }
        if loss == 1 { denied.agent_accessibility = false }
        let staleSession = runtime.viewerSession
        runtime.updateStatus(loss == 2 ? nil : denied)
        #expect(runtime.eventLog.events.isEmpty)
        runtime.receiveEvents([event(1)], session: runtime.viewerSession)
        #expect(runtime.eventLog.events.isEmpty)
        runtime.updateStatus(readyStatus())
        runtime.receiveEvents([event(2)], session: staleSession)
        #expect(runtime.eventLog.events.isEmpty)
    }
}
