import Foundation
import Darwin
import AppKit
import ApplicationServices
import Carbon
import IOKit.hid
import UserNotifications
import ReKeyIPC
import ReKeyModel

@MainActor final class Agent {
    var connection: NSXPCConnection?
    var lastApp = ""
    var lastSource = ""
    var lastSecure = true
    var viewerLease = ViewerLease()
    var viewerRequestInFlight = false
    var busy = false
    var store = ConfigurationStore()
    var processes: [Process] = []
    var lastAutoSelections: [String: AutoSelect] = [:]
    var pauseShortcutRef: EventHotKeyRef?
    var hid: IOHIDManager?
    var previousDeviceIDs: Set<DeviceID> = []
    var devicePoll = 0
    var shortcutRefs: [EventHotKeyRef] = []
    var shortcutTargets: [UInt32: String] = [:]
    var installedShortcuts: [String: Shortcut] = [:]
    var eventHandler: EventHandlerRef?
    func installShortcuts() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return OSStatus(eventNotHandledErr) }
            let receiver = Unmanaged<Agent>.fromOpaque(context).takeUnretainedValue()
            let value = id.id
            Task { @MainActor in receiver.handleShortcut(value) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(35, UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x52654B79, id: 0), GetApplicationEventTarget(), 0, &ref)
        if let ref { pauseShortcutRef = ref }
    }
    func updateShortcuts(_ config: Configuration) {
        let wanted = Dictionary(uniqueKeysWithValues: config.profiles.compactMap { p in p.shortcut.map { (p.id, $0) } })
        guard wanted != installedShortcuts else { return }
        for ref in shortcutRefs { UnregisterEventHotKey(ref) }
        shortcutRefs.removeAll()
        shortcutTargets = [:]
        for (offset, item) in wanted.sorted(by: { $0.key < $1.key }).enumerated() {
            guard let code = KeyCatalog.macKeyCodes.first(where: { $0.value == item.value.key })?.key else { continue }
            let flags: [String: Int] = ["control": controlKey, "option": optionKey, "shift": shiftKey, "command": cmdKey]
            let mask = item.value.modifiers.reduce(UInt32(0)) { $0 | UInt32(flags[$1] ?? 0) }
            let id = UInt32(offset + 1)
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(UInt32(code), mask, EventHotKeyID(signature: 0x52654B79, id: id), GetApplicationEventTarget(), 0, &ref) == noErr, let ref { shortcutRefs.append(ref); shortcutTargets[id] = item.key }
        }
        installedShortcuts = wanted
    }
    func handleShortcut(_ id: UInt32) {
        do {
            try store.update { config in
                if id == 0 { config.global.paused.toggle() }
                else if let profile = shortcutTargets[id], config.profiles.contains(where: { $0.id == profile }) { config.select(profile) }
            }
        } catch { NSLog("ReKey Agent: configuration transaction failed") }
    }
    func proxy() -> ReKeyControl? {
        if connection == nil {
            let c = NSXPCConnection(machServiceName: "jp.example.rekey.core", options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: ReKeyControl.self)
            c.invalidationHandler = { @Sendable [weak self] in Task { @MainActor in self?.connection = nil; self?.busy = false; self?.viewerLease.update(requested: false); self?.viewerRequestInFlight = false } }
            c.interruptionHandler = { @Sendable [weak self] in Task { @MainActor in self?.busy = false; self?.viewerLease.update(requested: false); self?.viewerRequestInFlight = false } }
            c.resume(); connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { @Sendable [weak self] _ in Task { @MainActor in self?.busy = false; self?.viewerLease.update(requested: false); self?.viewerRequestInFlight = false } } as? ReKeyControl
    }
    func tick() {
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let ref = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let source = TISGetInputSourceProperty(ref, kTISPropertyInputSourceID).map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? ""
        var secure = true
        let accessibility = AXIsProcessTrusted()
        if accessibility && viewerLease.allowsFocusInspection() {
            var focused: CFTypeRef?
            if AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), "AXFocusedUIElement" as CFString, &focused) == .success, let focused {
                let element = unsafeDowncast(focused, to: AXUIElement.self)
                func attribute(_ name: String) -> FocusAttribute {
                    var value: CFTypeRef?
                    switch AXUIElementCopyAttributeValue(element, name as CFString, &value) {
                    case .success: return (value as? String).map(FocusAttribute.value) ?? .unavailable
                    case .attributeUnsupported, .noValue: return .absent
                    default: return .unavailable
                    }
                }
                secure = FocusPrivacy.suppressesEvents(role: attribute(kAXRoleAttribute), subrole: attribute(kAXSubroleAttribute), secureInput: false)
            }
        }
        secure = secure || IsSecureEventInputEnabled()
        devicePoll += 1
        if app != lastApp || devicePoll % 10 == 0 { automaticProfile(app: app) }
        let remote = proxy()
        if !viewerRequestInFlight, let remote {
            viewerRequestInFlight = true
            remote.viewerRequested { [weak self] requested in
                Task { @MainActor in
                    guard let self else { return }
                    self.viewerRequestInFlight = false
                    self.viewerLease.update(requested: requested)
                }
            }
        }
        remote?.context(app: app, inputSource: source, secure: secure, accessibility: accessibility) { _ in }
        lastApp = app; lastSource = source; lastSecure = secure
        processes.removeAll { !$0.isRunning }
        if !busy, let remote {
            busy = true
            remote.actions { [weak self] data in
                let actions = (try? JSONDecoder().decode([JSONValue].self, from: data)) ?? []
                Task { @MainActor in guard let self else { return }; for a in actions { self.execute(a) }; self.busy = false }
            }
        }
    }
    func automaticProfile(app: String) {
        guard let c = try? store.load() else { return }
        updateShortcuts(c)
        if hid == nil {
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
            IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6] as CFDictionary)
            hid = manager
        }
        let devices = hid.flatMap { IOHIDManagerCopyDevices($0) as? Set<IOHIDDevice> } ?? []
        let connected = devices.map { d in
            DeviceID(vendor_id: (IOHIDDeviceGetProperty(d, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0, product_id: (IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0, serial: IOHIDDeviceGetProperty(d, kIOHIDSerialNumberKey as CFString) as? String)
        }
        let currentIDs = Set(connected)
        let currentSelections = Dictionary(uniqueKeysWithValues: c.profiles.map { ($0.id, $0.auto_select) })
        guard app != lastApp || currentIDs != previousDeviceIDs || currentSelections != lastAutoSelections else { return }
        previousDeviceIDs = currentIDs; lastAutoSelections = currentSelections
        let target = c.profiles.first { p in
            let conditions = p.auto_select
            guard !conditions.frontmost_app.isEmpty || !conditions.device.isEmpty else { return false }
            let appMatches = conditions.frontmost_app.isEmpty || conditions.frontmost_app.contains { pattern in (try? NSRegularExpression(pattern: pattern).firstMatch(in: app, range: NSRange(app.startIndex..., in: app))) != nil }
            let deviceMatches = conditions.device.isEmpty || conditions.device.contains { wanted in connected.contains { found in wanted.vendor_id == found.vendor_id && wanted.product_id == found.product_id && (wanted.serial == nil || wanted.serial == found.serial) } }
            return appMatches && deviceMatches
        }
        guard let target, target.id != c.activeProfile.id else { return }
        do {
            try store.update { latest in
                guard latest.profiles.contains(where: { $0.id == target.id }) else { return }
                latest.select(target.id)
            }
        } catch { NSLog("ReKey Agent: automatic profile transaction failed") }
    }
    func requestPermissions() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    func execute(_ action: JSONValue) {
        if let command = action["shell_command"]?.string {
            guard processes.count < 8 else { return }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = ["-lc", command]
            p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            do { try p.run(); processes.append(p) } catch { NSLog("ReKey Agent: user action could not be launched") }
        } else if let bundle = action["open_app"]?.string, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else if let pattern = action["select_input_source"]?.string {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return }
            let all = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
            for source in all {
                guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
                let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
                if re.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil { TISSelectInputSource(source); break }
            }
        } else if let message = action["notify"]?.string {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                let content = UNMutableNotificationContent(); content.title = "ReKey"; content.body = message
                UNUserNotificationCenter.current().add(.init(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }
}
guard getuid() != 0 && geteuid() != 0 else {
    FileHandle.standardError.write(Data("ReKeyAgent must never run as root\n".utf8)); exit(77)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let agent = Agent()
agent.installShortcuts()
let permissionObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("jp.example.rekey.agent.request-permissions"), object: nil, queue: .main) { _ in Task { @MainActor in agent.requestPermissions() } }
if CommandLine.arguments.contains("--request-permissions") { agent.requestPermissions() }
let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in Task { @MainActor in agent.tick() } }
app.run()
