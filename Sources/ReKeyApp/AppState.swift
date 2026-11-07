import SwiftUI
import Combine
import AppKit
import IOKit.hid
import ServiceManagement
import ReKeyModel
import ReKeyIPC

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

// Publish UI values explicitly. Transport/task bookkeeping must never take part
// in SwiftUI Observation tracking in this long-lived menu bar process.
@MainActor final class AppState: ObservableObject {
    @Published var config = Configuration()
    @Published var page: SettingsPage? = .simple
    @Published var devices: [KeyboardDevice] = []
    @Published var selectedDevice = "all"
    @Published var error: String?
    @Published var saveStatus = "読み込み中…"
    @Published private(set) var recoveringServices = false {
        didSet { updateTerminationGate() }
    }
    @Published private(set) var updatePrepared = false {
        didSet { updateTerminationGate() }
    }
    @Published private(set) var unsafePendingUpdate = false {
        didSet { updateTerminationGate() }
    }
    @Published private(set) var updateWarning: String?
    @Published private(set) var serviceOperationInProgress = false
    private let updateRecovery: UpdateServiceRecovery
    private let updateOperationsOverride: UpdateServiceRecovery.Operations?
    private let buildOverride: String?
    private let monitorSystem: Bool
    var accessibility: Bool { runtime.agentAccessibilityReady }
    var inputMonitoringReady: Bool { runtime.inputMonitoringReady }
    var eventViewerReady: Bool { runtime.eventViewerReady }
    var driverActive: Bool { runtime.status?.driver_ready == true }
    let runtime: RuntimeClient
    private(set) var updates: UpdateController!
    private var runtimeChanges: AnyCancellable?
    var daemonStatus: String { runtime.status.map { $0.seized_devices > 0 && !$0.paused && !$0.conflict ? "稼働中" : $0.paused ? "一時停止中" : $0.conflict ? "Karabiner と競合" : "接続済み・入力待ち" } ?? "未接続" }
    @Published var importResult: ImportResult?
    @Published var showImportReview = false
    @Published var showWelcome = false
    @Published var showUninstall = false
    var uninstalling = false
    @Published var frontmostApp = ""
    private var saving: Task<Void, Never>?
    private var polling: Task<Void, Never>?
    private var lastData: Data?
    private var dirty = false
    private var resumeAfterSave = false
    private let store: ConfigurationStore
    private var hid: IOHIDManager?
    var profileIndex: Int { config.profiles.firstIndex(where: \.selected) ?? 0 }
    var profile: Profile { config.profiles[profileIndex] }
    var scopeLabel: String { selectedDevice == "all" ? "すべてのキーボード" : devices.first(where: { $0.id == selectedDevice })?.name ?? selectedDevice }
    var isPaused: Bool { config.global.paused || (runtime.status?.paused ?? false) }
    var operational: Bool { daemonStatus == "稼働中" && driverActive && !config.global.paused }
    var statusTitle: String { recoveringServices || updatePrepared ? "更新処理中" : isPaused ? "一時停止中" : operational ? "リマップ有効" : "セットアップが必要です" }
    var statusColor: Color { recoveringServices || updatePrepared ? .orange : isPaused ? .secondary : operational ? .green : .orange }
    init(store: ConfigurationStore = ConfigurationStore(), runtime: RuntimeClient = RuntimeClient(), startMonitoring: Bool = true,
         updateRecovery: UpdateServiceRecovery? = nil, updateOperations: UpdateServiceRecovery.Operations? = nil,
         buildOverride: String? = nil) {
        self.store = store
        self.runtime = runtime
        self.updateRecovery = updateRecovery ?? UpdateServiceRecovery()
        self.updateOperationsOverride = updateOperations
        self.buildOverride = buildOverride
        self.monitorSystem = startMonitoring
        // Runtime publishes status/errors only; EventViewer owns its own log updates.
        runtimeChanges = runtime.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        showWelcome = !FileManager.default.fileExists(atPath: store.url.path)
        reload()
        updates = UpdateController(automaticChecks: config.global.check_for_updates,
            prepare: { [weak self] in
                guard let self else { throw NSError(domain: "ReKey.Update", code: 1) }
                try await self.prepareServicesForUpdate()
            },
            preparationFailed: { [weak self] error in self?.handleUpdateFailure(error, preparation: true) },
            pendingInstallFailed: { [weak self] error in
                self?.updatePrepared = true
                self?.unsafePendingUpdate = true
                self?.updateWarning = "保留中の更新を安全に続行できません。「更新を確認」で更新をキャンセルしてください: \(error.localizedDescription)"
            },
            aborted: { [weak self] error in self?.handleUpdateFailure(error, preparation: false) })
        TerminationGate.verifyPendingUpdate = { [weak self] in
            guard let self else { return false }
            return self.verifyServicesBeforeTermination()
        }
        // Prevent an early quit before asynchronous startup recovery inspects
        // a record left by a previous process.
        if self.updateRecovery.hasPendingRecovery {
            updatePrepared = true
            unsafePendingUpdate = true
        }
        guard startMonitoring else { return }
        refreshSystem()
        Task {
            await recoverServicesAfterUpdate()
            do { try await retireLegacyOutputService() }
            catch { self.error = "旧入力サービスを停止できませんでした: \(error.localizedDescription)" }
        }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { return }
                self.refreshSystem()
                self.reloadIfChanged()
            }
        }
    }
    deinit { polling?.cancel(); saving?.cancel() }

    func reload(reloadEngine: Bool = false) {
        saving?.cancel(); saving = nil; resumeAfterSave = false
        do { let snapshot = try store.snapshot(); config = snapshot.configuration; updates?.setAutomaticChecks(config.global.check_for_updates); lastData = snapshot.data; dirty = false; saveStatus = "設定を読み込みました"; if reloadEngine { runtime.reloadConfiguration() } }
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
    @discardableResult func flush() -> Bool {
        do {
            let saved = try store.save(config, basedOn: lastData)
            if resumeAfterSave && saved.data == lastData && !saved.configuration.global.paused { runtime.reloadConfiguration() }
            config = saved.configuration; lastData = saved.data; dirty = false; resumeAfterSave = false; saveStatus = "保存済み"
            if !saved.warnings.isEmpty { self.error = saved.warnings.joined(separator: "\n") }
            return true
        }
        catch { self.error = error.localizedDescription; saveStatus = "保存エラー"; return false }
    }
    func saveBeforeUpdate() throws {
        saving?.cancel(); saving = nil
        guard flush() else { throw NSError(domain: "ReKey.Update", code: 3, userInfo: [NSLocalizedDescriptionKey: "設定を保存できませんでした。"] ) }
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
    func requestAgentPermissions() { DistributedNotificationCenter.default().postNotificationName(NSNotification.Name(ReKeyServiceIdentity.permissionNotification()), object: nil, userInfo: nil, deliverImmediately: true) }
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
        guard !recoveringServices, !updatePrepared, !serviceOperationInProgress else { return }
        serviceOperationInProgress = true
        Task {
            defer { serviceOperationInProgress = false }
            do {
                try await retireLegacyOutputService()
                await registerCurrentServices()
            } catch { self.error = "旧入力サービスを停止できませんでした: \(error.localizedDescription)" }
        }
    }
    private func updateServiceOperations() -> UpdateServiceRecovery.Operations {
        if let updateOperationsOverride { return updateOperationsOverride }
        let services = ["core": SMAppService.daemon(plistName: ReKeyServiceIdentity.coreName() + ".plist"),
                        "agent": SMAppService.agent(plistName: ReKeyServiceIdentity.agentName() + ".plist")]
        return UpdateServiceRecovery.Operations(
            status: { name in
                guard let service = services[name] else { return .unavailable }
                switch service.status {
                case .enabled: return .enabled
                case .notRegistered: return .notRegistered
                case .requiresApproval: return .requiresApproval
                default: return .unavailable
                }
            },
            stop: { name in if let service = services[name] { try await service.unregister() } },
            start: { name in if let service = services[name] { try service.register() } }
        )
    }
    private var currentBuild: String? { buildOverride ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) }
    private func updateTerminationGate() {
        TerminationGate.updateServiceOperationInProgress = recoveringServices || unsafePendingUpdate
        TerminationGate.requiresPendingVerification = updatePrepared
    }
    func verifyServicesBeforeTermination() -> Bool {
        guard updatePrepared, !recoveringServices, !serviceOperationInProgress else { return false }
        do {
            try updateRecovery.verifyStopped(operations: updateServiceOperations())
            unsafePendingUpdate = false
            updateWarning = "更新を再開するか、キャンセルしてください。"
            return true
        } catch {
            unsafePendingUpdate = true
            updateWarning = "終了前に入力サービスの停止を確認できません。「更新を確認」で更新をキャンセルしてください: \(error.localizedDescription)"
            return false
        }
    }
    func prepareServicesForUpdate() async throws {
        guard !recoveringServices, !serviceOperationInProgress, let build = currentBuild else {
            throw NSError(domain: "ReKey.Update", code: 2, userInfo: [NSLocalizedDescriptionKey: "入力サービスの復旧中です。"])
        }
        recoveringServices = true
        defer { recoveringServices = false; if monitorSystem { refreshSystem() } }
        do {
            try saveBeforeUpdate()
            if updatePrepared { try await updateRecovery.ensureStopped(operations: updateServiceOperations()) }
            else { try await updateRecovery.prepare(build: build, operations: updateServiceOperations()) }
            updatePrepared = true
            unsafePendingUpdate = false
        } catch {
            // A staged update or a partially stopped service may remain until
            // Sparkle finishes cancelling. Don't allow install-on-quit in that gap.
            if updatePrepared || updateRecovery.hasPendingRecovery {
                updatePrepared = true
                unsafePendingUpdate = true
            }
            throw error
        }
    }
    @discardableResult func recoverServicesAfterUpdate(allowSameBuild: Bool = false) async -> Bool {
        guard !recoveringServices, !serviceOperationInProgress, let build = currentBuild else { return false }
        recoveringServices = true
        defer { recoveringServices = false; if monitorSystem { refreshSystem() } }
        do {
            try await updateRecovery.recover(build: build, operations: updateServiceOperations(), allowSameBuild: allowSameBuild)
            updatePrepared = false; unsafePendingUpdate = false; updateWarning = nil; return true
        } catch UpdateServiceRecovery.RecoveryError.pendingUpdate {
            updatePrepared = true
            unsafePendingUpdate = false
            updateWarning = "更新を再開するか、キャンセルしてください。"
            return false
        } catch {
            updatePrepared = updateRecovery.hasPendingRecovery
            unsafePendingUpdate = updatePrepared
            let message = "更新後の入力サービスを復旧できませんでした。バックグラウンド項目を確認してください: \(error.localizedDescription)"
            if updatePrepared { updateWarning = message } else { self.error = message }
            return false
        }
    }
    private func handleUpdateFailure(_ failure: Error, preparation: Bool) {
        guard preparation || updateRecovery.hasPendingRecovery || updatePrepared else { return }
        Task {
            let recovered = await recoverServicesAfterUpdate(allowSameBuild: true)
            if preparation {
                let message = "更新前に入力サービスを停止できませんでした。サービスを確認し、ReKey を再起動してから更新を再試行してください: \(failure.localizedDescription)"
                if recovered { self.error = message }
                else if updatePrepared { self.updateWarning = message + "\n" + (self.updateWarning ?? "入力サービスの復旧状態を確認してください。") }
                else { self.error = message + "\n" + (self.error ?? "入力サービスの復旧状態を確認してください。") }
            }
        }
    }
    private func retireLegacyOutputService() async throws {
        let legacy = SMAppService.daemon(plistName: "jp.example.rekey.vhid.plist")
        if legacy.status == .notFound { try? await legacy.unregister() }
        else if legacy.status != .notRegistered { try await legacy.unregister() }
    }
    private func registerCurrentServices() async {
        var services = [
            ("rekey-core", SMAppService.daemon(plistName: ReKeyServiceIdentity.coreName() + ".plist")),
            ("ReKey Agent", SMAppService.agent(plistName: ReKeyServiceIdentity.agentName() + ".plist"))
        ]
        if FileManager.default.isExecutableFile(atPath: driverDaemonPath) {
            services.insert(("Virtual HID Daemon", SMAppService.daemon(plistName: "org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon.plist")), at: 0)
        }
        var failures: [String] = []
        var needsApproval = false
        for (name, service) in services {
            if service.status == .enabled { continue }
            // A stale Background Items record must be removed before retrying.
            if service.status == .notFound { try? await service.unregister() }
            for attempt in 0..<5 {
                do { try service.register(); break }
                catch {
                    if service.status == .requiresApproval || service.status == .enabled { break }
                    let failure = error as NSError
                    if failure.domain == SMAppServiceErrorDomain && failure.code == 1 && attempt < 4 {
                        try? await Task.sleep(for: .milliseconds(250 * (1 << attempt)))
                        continue
                    }
                    failures.append("\(name): \(error.localizedDescription)")
                    break
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
        let services = [SMAppService.daemon(plistName: ReKeyServiceIdentity.coreName() + ".plist"), SMAppService.daemon(plistName: "jp.example.rekey.vhid.plist"), SMAppService.agent(plistName: ReKeyServiceIdentity.agentName() + ".plist")]
        for service in services where service.status != .notRegistered && service.status != .notFound { try service.unregister() }
    }
    func restartServices() {
        guard !recoveringServices, !updatePrepared, !serviceOperationInProgress else { return }
        serviceOperationInProgress = true
        Task {
            defer { serviceOperationInProgress = false }
            do {
                let services = [SMAppService.daemon(plistName: ReKeyServiceIdentity.coreName() + ".plist"), SMAppService.daemon(plistName: "jp.example.rekey.vhid.plist"), SMAppService.agent(plistName: ReKeyServiceIdentity.agentName() + ".plist")]
                // The async overload waits for the old process to exit before re-registering.
                for service in services where service.status != .notRegistered && service.status != .notFound {
                    try await service.unregister()
                }
                await registerCurrentServices()
            } catch { self.error = error.localizedDescription }
        }
    }
    func unregisterServices() {
        guard !recoveringServices, !updatePrepared, !serviceOperationInProgress else { return }
        do { try stopServices(); refreshSystem() }
        catch { self.error = error.localizedDescription }
    }
    func uninstall(removeSettings: Bool) {
        guard !recoveringServices, !updatePrepared, !serviceOperationInProgress else { return }
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
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if frontmostApp != app { frontmostApp = app }
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
        let sorted = found.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
        if devices != sorted { devices = sorted }
    }
}
