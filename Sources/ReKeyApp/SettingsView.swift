import SwiftUI
import AppKit
import ReKeyModel

struct SettingsView: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard.fill").font(.system(size: 25)).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) { Text("ReKey").font(.title2.bold()); Text("Your keys. Your way.").font(.caption).foregroundStyle(.secondary) }
                }.padding(20).padding(.top, 8)
                List(SettingsPage.allCases, selection: $state.page) { page in Label(L(page.rawValue), systemImage: page.icon).tag(page).padding(.vertical, 5) }.listStyle(.sidebar)
                Divider().padding(.horizontal)
                VStack(alignment: .leading, spacing: 8) {
                    Label(state.statusTitle, systemImage: state.operational ? "checkmark.circle.fill" : "exclamationmark.circle.fill").font(.caption.weight(.medium)).foregroundStyle(state.statusColor)
                    Text("v0.1.0 · 開発版").font(.caption2).foregroundStyle(.tertiary)
                }.padding(20)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 250)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Text(L((state.page ?? .simple).rawValue)).font(.system(size: 26, weight: .bold))
                    Spacer()
                    Picker("プロファイル", selection: Binding(get: { state.profile.id }, set: { state.selectProfile($0) })) {
                        ForEach(state.config.profiles) { Text($0.name).tag($0.id) }
                    }.labelsHidden().frame(width: 170)
                    Button { state.togglePause() } label: { Image(systemName: state.isPaused ? "play.fill" : "pause.fill") }.help(state.isPaused ? "再開" : "一時停止")
                }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 18)
                if !state.operational && state.page != .permissions {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.shield").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L(state.isPaused ? "リマップは一時停止中です" : "入力エンジンは接続されていません")).font(.callout.weight(.medium))
                            Text("設定は編集・保存できます。システム全体への変換にはサービスのセットアップが必要です。").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("権限を確認") { state.page = .permissions }.controlSize(.small)
                    }.padding(14).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 28).padding(.bottom, 16)
                }
                Group {
                    switch state.page ?? .simple {
                    case .simple: SimpleMappingsView(state: state)
                    case .complex: ComplexRulesView(state: state)
                    case .layers: LayersView(state: state)
                    case .devices: DevicesView(state: state)
                    case .profiles: ProfilesView(state: state)
                    case .permissions: PermissionsView(state: state)
                    case .general: GeneralView(state: state)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                HStack {
                    Image(systemName: state.saveStatus == "保存エラー" ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(.secondary)
                    Text(L(state.saveStatus)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("EventViewer", systemImage: "waveform.path") { openWindow(id: "events") }.buttonStyle(.plain).font(.caption)
                }.padding(.horizontal, 28).padding(.vertical, 12)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .alert("ReKey", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) { Button("OK") { state.error = nil } } message: { Text(state.error ?? "") }
        .sheet(isPresented: $state.showImportReview) { ImportReview(state: state) }
        .sheet(isPresented: $state.showUninstall) { UninstallView(state: state) }
        .sheet(isPresented: $state.showWelcome) { WelcomeView(state: state) }
    }
}
struct ScopePicker: View {
    @Bindable var state: AppState
    var body: some View {
        HStack {
            Image(systemName: "keyboard").foregroundStyle(.secondary)
            Picker("対象", selection: $state.selectedDevice) {
                Text("すべてのキーボード").tag("all")
                ForEach(state.devices) { d in Text(d.name).tag(d.id) }
            }.frame(maxWidth: 360)
            Spacer()
        }.onChange(of: state.selectedDevice) { _, new in if let d = state.devices.first(where: { $0.id == new }) { state.ensureDevice(d) } }
    }
}
struct KeyPicker: View {
    var title: String
    @Binding var selection: String
    @State private var capture = false
    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(KeyCatalog.Category.allCases) { category in
                    Menu {
                        Picker(L(title), selection: $selection) {
                            ForEach(category.keys, id: \.self) { key in
                                Text(KeyCatalog.label(key)).tag(key)
                            }
                        }.pickerStyle(.inline).labelsHidden()
                    } label: {
                        if category.keys.contains(selection) {
                            Label(L(category.title), systemImage: "checkmark")
                        } else {
                            Text(L(category.title))
                        }
                    }
                }
            } label: {
                Text(KeyCatalog.label(selection))
            }
            .accessibilityLabel(L(title))
            .accessibilityValue(KeyCatalog.label(selection))
            Button { capture = true } label: { Image(systemName: "record.circle") }.buttonStyle(.borderless).help("キーを押して入力")
        }.sheet(isPresented: $capture) { CaptureSheet(selection: $selection) }
    }
}
struct CaptureSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard").font(.system(size: 42)).foregroundStyle(.tint)
            Text("割り当てるキーを押してください").font(.title3.bold())
            Text("修飾キー・英数・かなも入力できます。").foregroundStyle(.secondary)
            KeyCaptureRepresentable { selection = $0; dismiss() }.frame(width: 1, height: 1)
            Button("キャンセル", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        }.padding(40).frame(width: 430)
    }
}
struct KeyCaptureRepresentable: NSViewRepresentable {
    let onKey: (String) -> Void
    func makeNSView(context: Context) -> KeyCaptureNSView { let v = KeyCaptureNSView(); v.onKey = onKey; DispatchQueue.main.async { v.window?.makeFirstResponder(v) }; return v }
    func updateNSView(_ view: KeyCaptureNSView, context: Context) { view.onKey = onKey }
}
final class KeyCaptureNSView: NSView {
    var onKey: ((String) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { if let key = KeyCatalog.macKeyCodes[event.keyCode] { onKey?(key) } }
    override func flagsChanged(with event: NSEvent) { if let key = KeyCatalog.macKeyCodes[event.keyCode] { onKey?(key) } }
}
struct SimpleMappingsView: View {
    @Bindable var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("キーを、使いやすい場所へ。").font(.callout).foregroundStyle(.secondary)
            ScopePicker(state: state)
            VStack(spacing: 0) {
                HStack { Text("変更前のキー"); Spacer(); Image(systemName: "arrow.right"); Spacer(); Text("変更後のキー"); Spacer().frame(width: 40) }.font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(16).background(.quaternary.opacity(0.4))
                if state.simpleMappings.isEmpty {
                    ContentUnavailableView { Label("リマップを追加", systemImage: "keyboard") } description: { Text("Caps Lock を Control に、英数をかなに。\nキーボードごとに、自分だけの配列を作れます。") } actions: { Button("最初のリマップを追加", systemImage: "plus") { state.simpleMappings.append(.init()) }.buttonStyle(.borderedProminent) }.padding(.vertical, 32)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(state.simpleMappings.enumerated()), id: \.element.id) { index, mapping in
                                HStack(spacing: 20) {
                                    KeyPicker(title: "変更前", selection: Binding(get: { mapping.from.key }, set: { state.simpleMappings[index].from.key = $0 }))
                                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                                    KeyPicker(title: "変更後", selection: Binding(get: { mapping.to.first?.key ?? "a" }, set: { state.simpleMappings[index].to = [.init($0)] }))
                                    Button(role: .destructive) { state.simpleMappings.remove(at: index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("削除")
                                }.padding(16)
                                if index < state.simpleMappings.count - 1 { Divider().padding(.horizontal, 16) }
                            }
                        }
                    }
                }
            }.background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5)))
            if !state.simpleMappings.isEmpty { Button("リマップを追加", systemImage: "plus") { state.simpleMappings.append(.init()) } }
            HStack(alignment: .top) { Image(systemName: "info.circle"); Text("デバイス固有の設定を優先して適用します。単純リマップ後のキーで複合ルールを評価し、出力を再変換しません。") }.font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 28).padding(.bottom, 24)
    }
}
struct ImportReview: View {
    @Bindable var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("設定をインポート").font(.title2.bold())
            Text("\(state.importResult?.profiles.count ?? 0) 個のプロファイルを追加します。既存のプロファイルは保持されます。")
            List {
                ForEach(state.importResult?.profiles ?? []) { p in VStack(alignment: .leading) { Text(p.name).bold(); Text("\(p.simple.count) リマップ · \(p.rules.count) ルール · \(p.devices.count) デバイス").foregroundStyle(.secondary) } }
                ForEach(state.importResult?.warnings ?? [], id: \.self) { warning in Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }.frame(height: 260)
            HStack { Spacer(); Button("キャンセル") { state.showImportReview = false }; Button("インポート") { state.commitImport() }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 580)
    }
}
struct WelcomeView: View {
    @Bindable var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "keyboard.fill").font(.system(size: 52)).foregroundStyle(.tint)
            Text("ReKey へようこそ").font(.largeTitle.bold())
            Text("使うキーボードに、あなたのルールを。").font(.title3).foregroundStyle(.secondary)
            Divider()
            Label("システム機能拡張 — 仮想キーボードを提供", systemImage: "puzzlepiece.extension")
            Label("バックグラウンドサービス — 入力を変換", systemImage: "gearshape.2")
            Label("入力監視 — Core がキーボード入力を取得", systemImage: "waveform.path")
            Label("アクセシビリティ — Agent が入力欄の安全を確認", systemImage: "accessibility")
            Text("この開発版では設定編集から始められます。ドライバとサービスの準備状況は「権限」で確認できます。").font(.callout).foregroundStyle(.secondary)
            HStack { Button("設定から始める") { state.showWelcome = false; state.flush() }; Spacer(); Button("セットアップを確認") { state.page = .permissions; state.showWelcome = false; state.flush() }.buttonStyle(.borderedProminent) }
        }.padding(36).frame(width: 580)
    }
}

struct UninstallView: View {
    @Bindable var state: AppState
    @State private var removeSettings = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ReKey をアンインストール").font(.title2.bold())
            Text("入力サービスとログイン項目の登録を解除し、ReKey をゴミ箱へ移動します。")
            Toggle("設定とバックアップもゴミ箱へ移動", isOn: $removeSettings)
            Text("Karabiner の共有ドライバと設定は保持します。").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("キャンセル") { state.showUninstall = false }; Button("アンインストール", role: .destructive) { state.uninstall(removeSettings: removeSettings) } }
        }.padding(28).frame(width: 520)
    }
}
