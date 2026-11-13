import Foundation
import Combine
import ReKeyModel
import ReKeyIPC

struct RuntimeStatus: Decodable, Equatable, Sendable {
    var paused: Bool
    var driver_ready: Bool
    var agent_accessibility: Bool?
    var input_monitoring: Bool?
    var seized_devices: Int
    var conflict: Bool
    var error: String
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
@MainActor final class RuntimeClient: ObservableObject {
    @Published private(set) var status: RuntimeStatus?
    var inputMonitoringReady: Bool { status?.input_monitoring == true }
    var agentAccessibilityReady: Bool { status?.agent_accessibility == true }
    var eventViewerReady: Bool { inputMonitoringReady && agentAccessibilityReady }
    var connectionError: String?
    let eventLog = EventLog()
    private(set) var viewing = false
    private(set) var viewerSession: UInt64 = 0
    private var viewerSuspended = false
    private let serviceName: String
    init(serviceName: String? = nil) { self.serviceName = serviceName ?? ReKeyServiceIdentity.coreName() }
    private var connection: NSXPCConnection?
    private var statusInFlight = false
    private var eventsInFlight = false
    func connect() {
        guard connection == nil else { return }
        let c = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: ReKeyControl.self)
        c.invalidationHandler = { @Sendable [weak self] in Task { @MainActor in self?.connection = nil; self?.updateStatus(nil); self?.statusInFlight = false; self?.eventsInFlight = false } }
        c.interruptionHandler = { @Sendable [weak self] in Task { @MainActor in self?.updateStatus(nil); self?.statusInFlight = false; self?.eventsInFlight = false } }
        c.resume(); connection = c
    }
    func refresh() {
        connect(); guard !statusInFlight else { return }
        statusInFlight = true
        guard let remote = connection?.remoteObjectProxyWithErrorHandler({ @Sendable [weak self] error in
            let message = error.localizedDescription
            Task { @MainActor in if self?.connectionError != message { self?.connectionError = message }; self?.updateStatus(nil); self?.statusInFlight = false }
        }) as? ReKeyControl else { statusInFlight = false; return }
        remote.status { @Sendable [weak self] text in
            let decoded = try? JSONDecoder().decode(RuntimeStatus.self, from: Data(text.utf8))
            Task { @MainActor in self?.updateStatus(decoded); if self?.connectionError != nil { self?.connectionError = nil }; self?.statusInFlight = false }
        }
    }
    func pollEvents() {
        guard viewing, !eventsInFlight else { return }
        viewerSuspended = false
        connect(); eventsInFlight = true
        guard let remote = connection?.remoteObjectProxyWithErrorHandler({ @Sendable [weak self] _ in Task { @MainActor in self?.eventsInFlight = false } }) as? ReKeyControl else { eventsInFlight = false; return }
        let session = viewerSession
        remote.events(enabled: true) { @Sendable [weak self] data in
            let batch = (try? JSONDecoder().decode([TraceEvent].self, from: data)) ?? []
            Task { @MainActor in
                guard let self else { return }
                self.receiveEvents(batch, session: session)
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
    func updateStatus(_ value: RuntimeStatus?) {
        guard value != status else { return }
        // Clear immediately when the Agent heartbeat or either permission is lost.
        if value?.input_monitoring != true || value?.agent_accessibility != true {
            viewerSession &+= 1
            eventLog.clear()
        }
        status = value
    }
    func startViewer() {
        viewerSession &+= 1
        viewing = true
        viewerSuspended = false
        eventLog.clear()
    }
    func receiveEvents(_ batch: [TraceEvent], session: UInt64) {
        guard viewing, session == viewerSession, eventViewerReady else { return }
        eventLog.append(batch)
    }
    func suspendViewer() {
        guard !viewerSuspended else { return }
        viewerSuspended = true
        viewerSession &+= 1
        eventLog.clear()
        (connection?.remoteObjectProxyWithErrorHandler { @Sendable _ in } as? ReKeyControl)?.events(enabled: false) { _ in }
    }
    func stopViewer() {
        guard viewing else { return }
        viewing = false; viewerSession &+= 1; eventLog.clear()
        (connection?.remoteObjectProxyWithErrorHandler { @Sendable _ in } as? ReKeyControl)?.events(enabled: false) { _ in }
    }
}

// This publisher is consumed only by EventViewer, never the menu/settings model.
@MainActor final class EventLog: ObservableObject {
    static let capacity = 2000
    @Published private(set) var events: [TraceEvent] = []

    func append(_ batch: [TraceEvent]) {
        guard !batch.isEmpty else { return }
        let incoming = batch.suffix(Self.capacity)
        let keep = Self.capacity - incoming.count
        events = Array(events.suffix(keep)) + incoming
    }
    func clear() {
        if !events.isEmpty { events = [] }
    }
}
