import SwiftUI
import AppKit
import ServiceManagement
import ReKeyModel

struct DevicesView: View {
    @ObservedObject var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("接続したキーボードを、自動で識別します。").foregroundStyle(.secondary)
                if state.devices.isEmpty { ContentUnavailableView("キーボードが見つかりません", systemImage: "keyboard", description: Text("キーボードを接続して再読込してください。")) }
                ForEach(state.devices) { d in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: d.builtin ? "laptopcomputer" : "keyboard").font(.system(size: 28)).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 4) { Text(d.name).font(.headline); Text("\(d.transport) · VID \(d.identity.vendor_id) / PID \(d.identity.product_id)" + (d.identity.serial.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                            Spacer()
                            Text(L(d.builtin ? "内蔵" : "外付け")).font(.caption).padding(.horizontal, 9).padding(.vertical, 4).background(.quaternary, in: Capsule())
                        }
                        Divider()
                        Toggle("このキーボードを変更対象にする", isOn: setting(d, \.ignore, invert: true))
                        if !d.builtin { Toggle("接続中は内蔵キーボードを無効化", isOn: setting(d, \.disable_builtin_when_connected)) }
                        Picker("キーボード種別", selection: Binding(get: { state.profile.devices.first(where: { $0.id == d.identity })?.keyboard_type ?? "auto" }, set: { value in state.ensureDevice(d); if let i = state.profile.devices.firstIndex(where: { $0.id == d.identity }) { state.config.profiles[state.profileIndex].devices[i].keyboard_type = value; state.changed() } })) {
                            Text("自動検出").tag("auto"); Text("ANSI").tag("ansi"); Text("ISO").tag("iso"); Text("JIS").tag("jis")
                        }
                        Toggle("F キーを輝度・音量などの標準機能として使用", isOn: setting(d, \.fn_keys_as_media))
                        Button("このキーボードのリマップを編集", systemImage: "arrow.left.arrow.right") { state.ensureDevice(d); state.selectedDevice = d.id; state.page = .simple }
                    }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5)))
                }
                Button("デバイスを再読込", systemImage: "arrow.clockwise") { state.refreshDevices() }
            }.padding(.horizontal, 28).padding(.bottom, 24)
        }
    }
    func setting(_ d: KeyboardDevice, _ path: WritableKeyPath<DeviceSettings, Bool>, invert: Bool = false) -> Binding<Bool> {
        Binding(get: {
            let value = state.profile.devices.first(where: { $0.id == d.identity })?[keyPath: path] ?? DeviceSettings(id: d.identity)[keyPath: path]
            return invert ? !value : value
        }, set: { new in
            state.ensureDevice(d)
            if let i = state.profile.devices.firstIndex(where: { $0.id == d.identity }) { state.config.profiles[state.profileIndex].devices[i][keyPath: path] = invert ? !new : new; state.changed() }
        })
    }
}
struct ProfilesView: View {
    @ObservedObject var state: AppState
    @State private var deleting: Profile?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("仕事、アプリ、キーボードに合わせて切り替える。").foregroundStyle(.secondary)
            List {
                ForEach(Array(state.config.profiles.enumerated()), id: \.element.id) { i, p in
                    HStack {
                        Button { state.selectProfile(p.id) } label: { Image(systemName: p.selected ? "checkmark.circle.fill" : "circle").foregroundStyle(p.selected ? Color.accentColor : .secondary) }.buttonStyle(.plain).help("このプロファイルを使用")
                        TextField("プロファイル名", text: Binding(get: { p.name }, set: { state.config.profiles[i].name = $0; state.changed() })).textFieldStyle(.plain)
                        Spacer()
                        Text("\(p.simple.count) リマップ · \(p.rules.count) ルール").font(.caption).foregroundStyle(.secondary)
                        Button("複製") { var copy = p; copy.id = UUID().uuidString; copy.name += " のコピー"; copy.selected = false; state.config.profiles.append(copy); state.changed() }
                        Button(role: .destructive) { deleting = p } label: { Image(systemName: "trash") }.disabled(state.config.profiles.count == 1)
                    }.padding(.vertical, 10)
                }
            }.listStyle(.inset).frame(minHeight: 140, maxHeight: 260)
            HStack {
                Button("プロファイルを追加", systemImage: "plus") { var p = Profile(name: "新しいプロファイル"); p.selected = false; state.config.profiles.append(p); state.changed() }
                Spacer(); Button("インポート…", systemImage: "square.and.arrow.down") { state.importFile() }; Button("書き出す…", systemImage: "square.and.arrow.up") { state.exportFile(profileOnly: true) }
            }
            GroupBox("キーボードショートカット · \(state.profile.name)") {
                HStack {
                    Toggle("⌃⌥⌘", isOn: Binding(get: { state.profile.shortcut != nil }, set: { state.config.profiles[state.profileIndex].shortcut = $0 ? .init() : nil; state.changed() }))
                    if let shortcut = state.profile.shortcut { KeyPicker(title: "ショートカットのキー", selection: Binding(get: { shortcut.key }, set: { state.config.profiles[state.profileIndex].shortcut?.key = $0; state.changed() })) }
                }.padding(8)
            }
            GroupBox("自動切替 · \(state.profile.name)") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("最前面アプリの bundle ID（正規表現、1 行ずつ）").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: Binding(get: { state.profile.auto_select.frontmost_app.joined(separator: "\n") }, set: { state.config.profiles[state.profileIndex].auto_select.frontmost_app = $0.split(separator: "\n").map(String.init); state.changed() })).font(.system(.body, design: .monospaced)).frame(height: 66)
                    Text("例: ^com\\.apple\\.Terminal$").font(.caption).foregroundStyle(.secondary)
                    Text("現在のアプリ: \(state.frontmostApp)").font(.caption).textSelection(.enabled)
                    Divider()
                    ForEach(state.devices) { d in
                        Toggle(d.name, isOn: Binding(get: { state.profile.auto_select.device.contains(d.identity) }, set: { enabled in if enabled { state.config.profiles[state.profileIndex].auto_select.device.append(d.identity) } else { state.config.profiles[state.profileIndex].auto_select.device.removeAll { $0 == d.identity } }; state.changed() }))
                    }
                }.padding(10)
            }
            Spacer()
        }.padding(.horizontal, 28).padding(.bottom, 24)
        .confirmationDialog("「\(deleting?.name ?? "")」を削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("削除", role: .destructive) { if let p = deleting { state.config.profiles.removeAll { $0.id == p.id }; if p.selected { state.config.profiles[0].selected = true }; state.changed(); deleting = nil } }
        }
    }
}
struct PermissionsView: View {
    @ObservedObject var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("入力を扱うために、必要なアクセスを確認します。").foregroundStyle(.secondary)
                permission("入力監視", icon: "waveform.path", status: state.inputMonitoringReady ? "許可済み" : "未許可", ready: state.inputMonitoringReady, description: "rekey-core のみ許可してください。場所は /Applications/ReKey.app/Contents/Library/HelperTools/rekey-core です。Finder で選択された rekey-core をシステム設定の入力監視リストに追加し、オンにしてください。許可後に「入力サービスを再起動」を押してください。") { state.requestInputMonitoring() }
                permission("アクセシビリティ", icon: "accessibility", status: state.accessibility ? "許可済み" : "EventViewer 使用時のみ必要", ready: state.accessibility, description: "通常のリマップには不要です。EventViewer のパスワード欄確認にのみ使用します。必要な場合は ReKeyAgent のみ許可してください。ReKey の許可は不要です。") { state.requestAccessibility(); state.openPrivacy("Privacy_Accessibility") }
                permission("仮想 HID ドライバ", icon: "puzzlepiece.extension", status: state.driverActive ? "接続済み（評価用）" : "未接続", ready: state.driverActive, description: "開発版は Karabiner の公開ドライバを利用します。「確認する」で接続用デーモンも登録します。バックグラウンド項目とドライバ拡張を許可してください。") { state.setupDriver() }
                permission("入力サービス", icon: "gearshape.2", status: state.daemonStatus, ready: state.daemonStatus == "稼働中", description: "rekey-core が入力の取得・変換・仮想 HID 出力を行います。root サービスは1つです。ReKeyAgent はユーザー権限で動作します。") { if let u = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(u) } }
                HStack { Button("入力サービスを登録") { state.registerServices() }; Button("登録を解除") { state.unregisterServices() }; Button("入力サービスを再起動") { state.restartServices() } }.disabled(state.recoveringServices)
                if let runtimeError = state.runtime.status?.error, !runtimeError.isEmpty { Text(runtimeError).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                GroupBox {
                    Label("Karabiner と同時にキーボードを占有しないでください。既存のリマッパーが稼働している場合、ReKey は自動的に入力を奪いません。", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary).padding(8)
                }
                Button("状態を再確認", systemImage: "arrow.clockwise") { state.refreshSystem() }
            }.padding(.horizontal, 28).padding(.bottom, 24)
        }
    }
    func permission(_ title: String, icon: String, status: String, ready: Bool, description: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading, spacing: 6) { HStack { Text(L(title)).font(.headline); Text(L(status)).font(.caption).foregroundStyle(ready ? .green : .orange) }; Text(L(description)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Spacer(); Button(L(ready ? "設定を開く" : "確認する"), action: action)
        }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5)))
    }
}
struct GeneralView: View {
    @AppStorage("language") private var language = "ja"
    @ObservedObject var state: AppState
    var body: some View {
        Form {
            Section("言語") { Picker("言語", selection: $language) { Text("日本語").tag("ja"); Text("English").tag("en"); Text("システム設定に従う").tag("system") } }
            Section("起動と終了") {
                Toggle("ログイン時に ReKey を起動", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { state.setLogin($0) }))
                Toggle("終了時にリマップを無効化", isOn: $state.config.global.disable_on_quit).onChange(of: state.config.global.disable_on_quit) { state.changed() }
            }
            Section("判定時間") {
                Stepper("単押し: \(state.config.global.thresholds_ms.alone) ms", value: $state.config.global.thresholds_ms.alone, in: 1...5000, step: 10).onChange(of: state.config.global.thresholds_ms.alone) { state.changed() }
                Stepper("長押し: \(state.config.global.thresholds_ms.held_down) ms", value: $state.config.global.thresholds_ms.held_down, in: 1...5000, step: 10).onChange(of: state.config.global.thresholds_ms.held_down) { state.changed() }
                Stepper("同時押し: \(state.config.global.thresholds_ms.simultaneous) ms", value: $state.config.global.thresholds_ms.simultaneous, in: 1...500, step: 5).onChange(of: state.config.global.thresholds_ms.simultaneous) { state.changed() }
            }
            Section("設定ファイル") {
                LabeledContent("保存先", value: "~/Library/Application Support/ReKey/rekey.json").font(.callout)
                Text("変更は 300 ms 後に自動保存。直近 20 世代のバックアップを保持します。").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Finder で表示") { state.revealConfig() }; Button("再読込") { state.reload(reloadEngine: true) }; Button("すべて書き出す…") { state.exportFile() } }
            }
            Section("アップデート") {
                Toggle("更新を自動的に確認", isOn: $state.config.global.check_for_updates)
                    .onChange(of: state.config.global.check_for_updates) { state.updates.setAutomaticChecks(state.config.global.check_for_updates); state.changed() }
                    .disabled(!state.updates.available)
                Button("今すぐ更新を確認") { state.updates.checkNow() }.disabled(!state.updates.available)
                Text(L(state.updates.available ? "更新の確認時に配信サーバーへ接続します。インストール時に管理者認証を求められる場合があります。" : "このビルドには更新配信先と公開鍵が設定されていません。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("ReKey について") {
                Text("ReKey \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") · macOS 27 / Apple Silicon").font(.callout)
            }
        }.formStyle(.grouped)
    }
}
struct EventViewer: View {
    @ObservedObject var state: AppState
    @ObservedObject private var log: EventLog
    @State private var paused = false
    init(state: AppState) {
        self.state = state
        self.log = state.runtime.eventLog
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) { Text("EventViewer").font(.largeTitle.bold()); Text("受信した入力と、変換後の出力を確認します。").foregroundStyle(.secondary) }
                Spacer()
                Button(L(paused ? "表示を再開" : "表示を停止"), systemImage: paused ? "play" : "pause") { paused.toggle() }
                Button("クリア", systemImage: "trash") { state.runtime.eventLog.clear() }
            }
            if !state.eventViewerReady {
                ContentUnavailableView { Label(L(state.runtime.status == nil ? "入力サービスへの接続待ち" : state.inputMonitoringReady ? "ReKeyAgent の権限と接続を確認してください" : "入力監視の許可が必要です"), systemImage: "waveform.path") } description: { Text("通常のリマップにはアクセシビリティは不要です。EventViewer では ReKeyAgent による入力欄の安全確認が必要です。") } actions: { Button("EventViewer のアクセスを許可") { state.requestAccessibility(); state.openPrivacy("Privacy_Accessibility") }; Button("権限を確認") { state.page = .permissions; NSApp.windows.first(where: { $0.title == "ReKey" })?.makeKeyAndOrderFront(nil) } }
            } else {
                Table(log.events) {
                    TableColumn("時刻") { e in Text(String(format: "%.3f", Double(e.time_ns)/1_000_000_000)).monospacedDigit() }.width(90)
                    TableColumn("デバイス") { e in VStack(alignment: .leading) { Text(e.device_name ?? "Device \(e.device)"); Text("\(e.vendor_id ?? 0):\(e.product_id ?? 0)").font(.caption2).foregroundStyle(.secondary) } }
                    TableColumn("入力") { e in eventLabel(e.input, down: e.input_down, modifiers: e.input_modifiers, event: e) }
                    TableColumn("出力") { e in eventLabel(e.output, down: e.output_down, modifiers: e.output_modifiers, event: e) }
                    TableColumn("ルール") { e in Text(e.rule_name ?? (e.rule < 0 ? "—" : "Rule \(e.rule + 1)")) }
                }
                if log.events.isEmpty { Text("イベントを待っています。セキュアな入力欄のイベントは表示しません。").foregroundStyle(.secondary).frame(maxWidth: .infinity) }
            }
            Label("最大 2,000 行 · ファイルには記録しません · セキュアな入力時は非表示", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
        }.padding(28)
        .task {
            state.runtime.startViewer()
            while !Task.isCancelled {
                // Polling also renews the viewing lease while AX is untrusted;
                // Core returns no events until the Agent confirms a safe focus.
                if !paused { state.runtime.pollEvents() }
                else { state.runtime.suspendViewer() }
                if !state.eventViewerReady { state.runtime.eventLog.clear() }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .onDisappear { state.runtime.stopViewer() }
    }
    func modifierLabel(_ mask: UInt8) -> String {
        [(UInt8(0x11), "⌃"), (0x22, "⇧"), (0x44, "⌥"), (0x88, "⌘")].filter { mask & $0.0 != 0 }.map(\.1).joined()
    }
    func eventLabel(_ code: UInt32, down: Bool, modifiers: UInt8, event: TraceEvent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(code == 0 ? "—" : "\(down ? "↓" : "↑") \(event.label(code))").font(.system(.body, design: .monospaced))
            if code != 0 { Text(String(format: "0x%02X / 0x%02X", code < 256 ? 7 : code >> 16, code < 256 ? code : code & 65535) + " · " + modifierLabel(modifiers)).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
