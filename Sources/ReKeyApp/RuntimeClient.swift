import Foundation
import ReKeyModel
import ReKeyIPC

struct RuntimeStatus: Decodable, Sendable {
    var paused: Bool
    var driver_ready: Bool
    var agent_accessibility: Bool?
    var input_monitoring: Bool?
    var seized_devices: Int
    var conflict: Bool
    var error: String
    var uid: UInt32
}
struct TraceEvent: Decodable, Identifiable, Sendable {
    var id = UUID()
    var time_ns: UInt64
    var device: Int
    var device_name: String?
    var vendor_id: Int?
    var product_id: Int?
    var input: UInt32
    var input_down: Bool
    var output: UInt32
    var output_down: Bool
    var input_modifiers: UInt8
    var output_modifiers: UInt8
    var rule: Int
    var rule_name: String?
    enum CodingKeys: String, CodingKey { case input_modifiers, output_modifiers, time_ns, device, device_name, vendor_id, product_id, input, input_down, output, output_down, rule, rule_name }
    func label(_ code: UInt32) -> String { code == 0 ? "—" : KeyCatalog.label(KeyCatalog.name(page: code < 256 ? 7 : code >> 16, usage: code < 256 ? code : code & 65535)) }
}
@MainActor @Observable final class RuntimeClient {
    var status: RuntimeStatus?
    var inputMonitoringReady: Bool { status?.input_monitoring == true }
    var agentAccessibilityReady: Bool { status?.agent_accessibility == true }
    var eventViewerReady: Bool { inputMonitoringReady && agentAccessibilityReady }
    var connectionError: String?
    var events: [TraceEvent] = []
    var viewing = false
    private let serviceName: String
    init(serviceName: String = "jp.example.rekey.core") { self.serviceName = serviceName }
    private var connection: NSXPCConnection?
    private var statusInFlight = false
    private var eventsInFlight = false
    func connect() {
        guard connection == nil else { return }
        let c = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: ReKeyControl.self)
        c.invalidationHandler = { @Sendable [weak self] in Task { @MainActor in self?.connection = nil; self?.status = nil; self?.statusInFlight = false; self?.eventsInFlight = false } }
        c.interruptionHandler = { @Sendable [weak self] in Task { @MainActor in self?.status = nil; self?.statusInFlight = false; self?.eventsInFlight = false } }
        c.resume(); connection = c
    }
    func refresh() {
        connect(); guard !statusInFlight else { return }
        statusInFlight = true
        guard let remote = connection?.remoteObjectProxyWithErrorHandler({ @Sendable [weak self] error in
            let message = error.localizedDescription
            Task { @MainActor in self?.connectionError = message; self?.status = nil; self?.statusInFlight = false }
        }) as? ReKeyControl else { statusInFlight = false; return }
        remote.status { @Sendable [weak self] text in
            let decoded = try? JSONDecoder().decode(RuntimeStatus.self, from: Data(text.utf8))
            Task { @MainActor in self?.status = decoded; self?.connectionError = nil; self?.statusInFlight = false }
        }
    }
    func pollEvents() {
        guard viewing, !eventsInFlight else { return }
        connect(); eventsInFlight = true
        guard let remote = connection?.remoteObjectProxyWithErrorHandler({ @Sendable [weak self] _ in Task { @MainActor in self?.eventsInFlight = false } }) as? ReKeyControl else { eventsInFlight = false; return }
        remote.events(enabled: true) { @Sendable [weak self] data in
            let batch = (try? JSONDecoder().decode([TraceEvent].self, from: data)) ?? []
            Task { @MainActor in
                guard let self else { return }
                if self.viewing { self.events.append(contentsOf: batch); if self.events.count > 2000 { self.events.removeFirst(self.events.count - 2000) } }
                self.eventsInFlight = false
            }
        }
    }
    func requestInputMonitoring() {
        connect()
        (connection?.remoteObjectProxyWithErrorHandler { @Sendable _ in } as? ReKeyControl)?.requestInputMonitoring { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func reloadConfiguration() {
        connect()
        (connection?.remoteObjectProxyWithErrorHandler { @Sendable _ in } as? ReKeyControl)?.reload { _ in }
    }
    func shutdown() { (connection?.remoteObjectProxyWithErrorHandler { @Sendable _ in } as? ReKeyControl)?.lifecycle(active: false) { _ in } }
    func suspendViewer() {
        events.removeAll()
        (connection?.remoteObjectProxyWithErrorHandler { @Sendable _ in } as? ReKeyControl)?.events(enabled: false) { _ in }
    }
    func stopViewer() {
        viewing = false; events.removeAll()
        (connection?.remoteObjectProxyWithErrorHandler { @Sendable _ in } as? ReKeyControl)?.events(enabled: false) { _ in }
    }
}
