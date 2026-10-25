import SwiftUI
import AppKit
import IOKit.hid
import ServiceManagement
import ReKeyModel

struct KeyboardDevice: Identifiable, Equatable {
    var id: String { identity.label }
    var identity: DeviceID
    var name: String
    var transport: String
    var builtin: Bool
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case simple = "単純リマップ", complex = "複合ルール", layers = "レイヤー", devices = "デバイス", profiles = "プロファイル", permissions = "権限", general = "その他"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .simple: "arrow.left.arrow.right"
        case .complex: "point.3.connected.trianglepath.dotted"
        case .layers: "square.3.layers.3d"
        case .devices: "keyboard"
        case .profiles: "person.crop.rectangle.stack"
        case .permissions: "lock.shield"
        case .general: "gearshape"
        }
    }
}

@MainActor @Observable final class AppState {
    var config = Configuration()
    var page: SettingsPage? = .simple
    var devices: [KeyboardDevice] = []
    var selectedDevice = "all"
    var error: String?
    var saveStatus = "読み込み中…"
    var accessibility: Bool { runtime.agentAccessibilityReady }
    var inputMonitoringReady: Bool { runtime.inputMonitoringReady }
    var eventViewerReady: Bool { runtime.eventViewerReady }
    var driverActive = false
    var karabinerRunning = false
    var runtime = RuntimeClient()
    var daemonStatus: String { runtime.status.map { $0.seized_devices > 0 && !$0.paused && !$0.conflict ? "稼働中" : $0.paused ? "一時停止中" : $0.conflict ? "Karabiner と競合" : "接続済み・入力待ち" } ?? "未接続" }
    var importResult: ImportResult?
    var showImportReview = false
    var showWelcome = false
    var showUninstall = false
    var uninstalling = false
    var frontmostApp = ""
    var saving: Task<Void, Never>?
    private var polling: Task<Void, Never>?
    private var lastData: Data?
    private var dirty = false
    private var resumeAfterSave = false
    private let store = ConfigurationStore()
    private var hid: IOHIDManager?
    var profileIndex: Int { config.profiles.firstIndex(where: \.selected) ?? 0 }
    var profile: Profile { config.profiles[profileIndex] }
    var scopeLabel: String { selectedDevice == "all" ? "すべてのキーボード" : devices.first(where: { $0.id == selectedDevice })?.name ?? selectedDevice }
    var isPaused: Bool { config.global.paused || (runtime.status?.paused ?? false) }
    var operational: Bool { daemonStatus == "稼働中" && driverActive && !config.global.paused }
    var statusTitle: String { isPaused ? "一時停止中" : operational ? "リマップ有効" : "セットアップが必要です" }
    var statusColor: Color { isPaused ? .secondary : operational ? .green : .orange }
    init() {
        showWelcome = !FileManager.default.fileExists(atPath: store.url.path)
        reload()
        refreshSystem()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { return }
                self.refreshSystem()
                self.reloadIfChanged()
            }
        }
    }
    func reload(reloadEngine: Bool = false) {
        saving?.cancel(); saving = nil; resumeAfterSave = false
        do { let snapshot = try store.snapshot(); config = snapshot.configuration; lastData = snapshot.data; dirty = false; saveStatus = "設定を読み込みました"; if reloadEngine { runtime.reloadConfiguration() } }
        catch { self.error = error.localizedDescription; saveStatus = "読み込みエラー" }
    }
    func reloadIfChanged() {
        guard !dirty, saving == nil, let data = try? Data(contentsOf: store.resolvedURL), data != lastData else { return }
        reload()
    }
    func changed() {
        dirty = true; saving?.cancel(); saveStatus = "保存中…"
        saving = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.flush()
            self.saving = nil
        }
    }
    func flush() {
        do {
            let saved = try store.save(config, basedOn: lastData)
            if resumeAfterSave && saved.data == lastData && !saved.configuration.global.paused { runtime.reloadConfiguration() }
            config = saved.configuration; lastData = saved.data; dirty = false; resumeAfterSave = false; saveStatus = "保存済み"
            if !saved.warnings.isEmpty { self.error = saved.warnings.joined(separator: "\n") }
        }
        catch { self.error = error.localizedDescription; saveStatus = "保存エラー" }
    }
    func selectProfile(_ id: String) { config.select(id); changed() }
    func togglePause() { resumeAfterSave = isPaused && !config.global.paused; config.global.paused = !isPaused; changed() }
    func deviceSettingsIndex() -> Int? {
        guard selectedDevice != "all" else { return nil }
        return profile.devices.firstIndex(where: { $0.id.label == selectedDevice })
    }
    func ensureDevice(_ d: KeyboardDevice) {
        if !profile.devices.contains(where: { $0.id == d.identity }) { config.profiles[profileIndex].devices.append(.init(id: d.identity)); changed() }
    }
    var simpleMappings: [SimpleMapping] {
        get { if let i = deviceSettingsIndex() { return profile.devices[i].simple }; return profile.simple }
        set { if let i = deviceSettingsIndex() { config.profiles[profileIndex].devices[i].simple = newValue } else { config.profiles[profileIndex].simple = newValue }; changed() }
    }
    var complexRules: [ComplexRule] {
        get { if let i = deviceSettingsIndex() { return profile.devices[i].rules }; return profile.rules }
        set { if let i = deviceSettingsIndex() { config.profiles[profileIndex].devices[i].rules = newValue } else { config.profiles[profileIndex].rules = newValue }; changed() }
    }
    var layers: [Layer] {
        get { if let i = deviceSettingsIndex() { return profile.devices[i].layers }; return profile.layers }
        set { if let i = deviceSettingsIndex() { config.profiles[profileIndex].devices[i].layers = newValue } else { config.profiles[profileIndex].layers = newValue }; changed() }
    }
    func validate(rules: [ComplexRule]? = nil, layers: [Layer]? = nil) throws {
        var candidate = config
        let p = profileIndex
        if let d = deviceSettingsIndex() {
            if let rules { candidate.profiles[p].devices[d].rules = rules }
            if let layers { candidate.profiles[p].devices[d].layers = layers }
        } else {
            if let rules { candidate.profiles[p].rules = rules }
            if let layers { candidate.profiles[p].layers = layers }
        }
        _ = try candidate.validated()
    }
    func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            if let own = try? Configuration.decode(data) { importResult = .init(profiles: own.profiles, warnings: []) }
            else { importResult = try KarabinerImporter.read(data) }
            showImportReview = true
        } catch { self.error = error.localizedDescription }
    }
    func commitImport() {
        guard let result = importResult else { return }
        for var p in result.profiles { p.id = UUID().uuidString; p.selected = false; config.profiles.append(p) }
        changed(); showImportReview = false; importResult = nil
    }
    func exportFile(profileOnly: Bool = false) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = profileOnly ? "\(profile.name).json" : "rekey.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var output = config
            if profileOnly { output.profiles = [profile] }
            try output.encoded().write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
    func revealConfig() { NSWorkspace.shared.selectFile(store.url.path, inFileViewerRootedAtPath: store.url.deletingLastPathComponent().path) }
    func openPrivacy(_ section: String) { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") { NSWorkspace.shared.open(url) } }
    func requestAgentPermissions() { DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("jp.example.rekey.agent.request-permissions"), object: nil, userInfo: nil, deliverImmediately: true) }
    func requestAccessibility() { requestAgentPermissions() }
    func requestInputMonitoring() {
        runtime.requestInputMonitoring()
        openPrivacy("Privacy_ListenEvent")
        let core = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/HelperTools/rekey-core")
        NSWorkspace.shared.activateFileViewerSelecting([core])
    }
    private let driverDaemonPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    func setupDriver() {
        guard FileManager.default.isExecutableFile(atPath: driverDaemonPath) else {
            error = "Karabiner の仮想 HID ドライバをインストールしてください。README のセットアップ手順を確認してください。"
            return
        }
        registerServices()
    }
    func registerServices() {
        var services = [
            ("rekey-vhid", SMAppService.daemon(plistName: "jp.example.rekey.vhid.plist")),
            ("rekey-core", SMAppService.daemon(plistName: "jp.example.rekey.core.plist")),
            ("ReKey Agent", SMAppService.agent(plistName: "jp.example.rekey.agent.plist"))
        ]
        if FileManager.default.isExecutableFile(atPath: driverDaemonPath) {
            services.insert(("Virtual HID Daemon", SMAppService.daemon(plistName: "org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon.plist")), at: 0)
        }
        var failures: [String] = []
        var needsApproval = false
        for (name, service) in services {
            if service.status == .enabled { continue }
            // A stale Background Items record must be removed before retrying.
            if service.status == .notFound { try? service.unregister() }
            do { try service.register() }
            catch {
                // register can throw EPERM while successfully creating an approval request.
                if service.status != .requiresApproval && service.status != .enabled {
                    failures.append("\(name): \(error.localizedDescription)")
                }
            }
            needsApproval = needsApproval || service.status == .requiresApproval
        }
        refreshSystem()
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
        if needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }
    private func stopServices() throws {
        // The official Virtual HID daemon is shared with other clients; keep it registered.
        let services = [SMAppService.daemon(plistName: "jp.example.rekey.core.plist"), SMAppService.daemon(plistName: "jp.example.rekey.vhid.plist"), SMAppService.agent(plistName: "jp.example.rekey.agent.plist")]
        for service in services where service.status != .notRegistered && service.status != .notFound { try service.unregister() }
    }
    func restartServices() {
        do { try stopServices(); registerServices() }
        catch { self.error = error.localizedDescription }
    }
    func unregisterServices() {
        do { try stopServices(); refreshSystem() }
        catch { self.error = error.localizedDescription }
    }
    func uninstall(removeSettings: Bool) {
        do {
            try stopServices()
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            saving?.cancel(); saving = nil; uninstalling = true; runtime.shutdown()
            var items = [Bundle.main.bundleURL]
            if removeSettings && FileManager.default.fileExists(atPath: store.url.deletingLastPathComponent().path) { items.append(store.url.deletingLastPathComponent()) }
            NSWorkspace.shared.recycle(items) { @Sendable _, error in
                let message = error?.localizedDescription
                Task { @MainActor in
                    if let message { self.error = message; self.showUninstall = false }
                    else { NSApp.terminate(nil) }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; config.global.start_at_login = enabled; changed() }
        catch { self.error = error.localizedDescription }
    }
    func refreshSystem() {
        frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        karabinerRunning = NSWorkspace.shared.runningApplications.contains { ($0.bundleIdentifier ?? "").contains("karabiner") || ($0.bundleIdentifier ?? "").contains("Karabiner") }
        driverActive = runtime.status?.driver_ready ?? false
        runtime.refresh()
        refreshDevices()
    }
    func refreshDevices() {
        if hid == nil {
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let matching: [String: Any] = [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6]
            IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
            hid = manager
        }
        guard let hid, let set = IOHIDManagerCopyDevices(hid) as? Set<IOHIDDevice> else { return }
        var found: [KeyboardDevice] = []
        for d in set {
            func prop(_ key: String) -> Any? { IOHIDDeviceGetProperty(d, key as CFString) }
            let name = prop(kIOHIDProductKey) as? String ?? "Keyboard"
            if name.contains("VirtualHID") || name.contains("ReKey Virtual") { continue }
            let identity = DeviceID(vendor_id: (prop(kIOHIDVendorIDKey) as? NSNumber)?.intValue ?? 0, product_id: (prop(kIOHIDProductIDKey) as? NSNumber)?.intValue ?? 0, serial: (prop(kIOHIDSerialNumberKey) as? String).flatMap { $0.isEmpty ? nil : $0 })
            if found.contains(where: { $0.identity == identity }) { continue }
            found.append(.init(identity: identity, name: name, transport: prop(kIOHIDTransportKey) as? String ?? "Unknown", builtin: (prop(kIOHIDBuiltInKey) as? NSNumber)?.boolValue ?? false))
        }
        devices = found.sorted { $0.name < $1.name }
    }
}
