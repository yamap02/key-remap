import Testing
import Foundation
@testable import ReKeyApp

@Test @MainActor func unavailableDaemonCallbackDoesNotRequireTheMainQueue() async throws {
    let client = RuntimeClient(serviceName: "jp.example.rekey.tests.missing.\(UUID().uuidString)")
    for _ in 0..<3 {
        client.connectionError = nil
        client.refresh()
        let deadline = ContinuousClock.now + .seconds(2)
        while client.connectionError == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(client.connectionError != nil)
        #expect(client.status == nil)
    }
    client.startViewer()
    client.pollEvents()
    client.reloadConfiguration()
    try await Task.sleep(for: .milliseconds(50))
    client.stopViewer()
    client.shutdown()
    #expect(client.eventLog.events.isEmpty)
}

// Missing fields from an older service and an expired Agent heartbeat must
// fail closed without depending on the settings app's own TCC permissions.
@Test @MainActor func permissionsComeFromTheProcessesThatUseThem() throws {
    let client = RuntimeClient()
    #expect(!client.inputMonitoringReady)
    #expect(!client.agentAccessibilityReady)
    #expect(!client.eventViewerReady)
    for input in [false, true] {
        for accessibility in [false, true] {
            let data = try JSONSerialization.data(withJSONObject: [
                "paused": false, "driver_ready": true, "seized_devices": 1,
                "conflict": false, "error": "", "uid": 501,
                "input_monitoring": input, "agent_accessibility": accessibility
            ])
            client.updateStatus(try JSONDecoder().decode(RuntimeStatus.self, from: data))
            #expect(client.inputMonitoringReady == input)
            #expect(client.agentAccessibilityReady == accessibility)
            #expect(client.eventViewerReady == (input && accessibility))
        }
    }
    // A service without Agent permission reporting cannot enable EventViewer.
    client.updateStatus(try JSONDecoder().decode(RuntimeStatus.self, from: Data(
        #"{"paused":false,"driver_ready":true,"input_monitoring":true,"seized_devices":1,"conflict":false,"error":"","uid":501}"#.utf8)))
    #expect(client.inputMonitoringReady)
    #expect(!client.agentAccessibilityReady)
    #expect(!client.eventViewerReady)
    client.updateStatus(nil)
    #expect(!client.eventViewerReady)
}
