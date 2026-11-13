import SwiftUI
import AppKit
import ReKeyModel
import ServiceManagement

@main struct ReKeyApp: App {
    @NSApplicationDelegateAdaptor(ReKeyApplicationDelegate.self) private var appDelegate
    @AppStorage("language") private var language = "ja"
    @StateObject private var state = AppState()
    var body: some Scene {
        Window("ReKey", id: "settings") {
            SettingsView(state: state).environment(\.locale, language == "system" ? .autoupdatingCurrent : Locale(identifier: language))
                .disabled(state.recoveringServices || state.updatePrepared)
                .frame(minWidth: 920, minHeight: 640)
        }
        .defaultSize(width: 1080, height: 760)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { OpenSettingsButton() }
            CommandMenu("ReKey") {
                Button(L(state.isPaused ? "再開" : "一時停止")) { state.togglePause() }.disabled(state.recoveringServices || state.updatePrepared)
                Button("設定を再読込") { state.reload(reloadEngine: true) }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(state.recoveringServices || state.updatePrepared)
                Button("設定をインポート…") { state.importFile() }.disabled(state.recoveringServices || state.updatePrepared)
                Button("設定を書き出す…") { state.exportFile() }.disabled(state.recoveringServices || state.updatePrepared)
            }
        }
        Window("ReKey EventViewer", id: "events") {
            EventViewer(state: state).environment(\.locale, language == "system" ? .autoupdatingCurrent : Locale(identifier: language)).frame(minWidth: 880, minHeight: 520)
        }.defaultSize(width: 1040, height: 640)
        MenuBarExtra {
            MenuContent(state: state).environment(\.locale, language == "system" ? .autoupdatingCurrent : Locale(identifier: language))
        } label: {
            Image(nsImage: state.operational ? AppIcons.active : state.isPaused ? AppIcons.paused : AppIcons.attention)
                .accessibilityLabel("ReKey · \(L(state.statusTitle))")
                .help("ReKey · \(L(state.statusTitle))")
        }
    }
}
// Commands cannot read openWindow from the App; it reopens the window even after it was closed.
struct OpenSettingsButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("設定を開く…") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }.keyboardShortcut(",") }
}
struct MenuContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("ReKey · \(L(state.statusTitle))")
        if state.updatePrepared {
            Text("更新処理中は入力サービスを停止します。準備済みの更新は終了時にインストールされる場合があります。")
            if let warning = state.updateWarning { Text(warning) }
            if state.unsafePendingUpdate {
                Button("入力サービスの停止を再確認") { _ = state.verifyServicesBeforeTermination() }
            }
            Button("更新を確認…") { state.updates.checkNow() }.disabled(!state.updates.available)
            Button("バックグラウンド項目を開く") { SMAppService.openSystemSettingsLoginItems() }
        }
        Divider()
        ForEach(state.config.profiles) { p in
            Button { state.selectProfile(p.id) } label: { if p.selected { Label(p.name, systemImage: "checkmark") } else { Text(p.name) } }
                .disabled(state.recoveringServices || state.updatePrepared)
        }
        Divider()
        Button(L(state.isPaused ? "リマップを再開" : "一時停止")) { state.togglePause() }.disabled(state.recoveringServices || state.updatePrepared)
        Button("設定を開く…") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
        Button("EventViewer を開く…") { openWindow(id: "events"); NSApp.activate(ignoringOtherApps: true) }
        Button("設定を再読込") { state.reload(reloadEngine: true) }.disabled(state.recoveringServices || state.updatePrepared)
        Divider()
        Button("ReKey をアンインストール…") { state.showUninstall = true; openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }.disabled(state.recoveringServices || state.updatePrepared)
        Button("ReKey を終了") { NSApp.terminate(nil) }.keyboardShortcut("q").disabled(state.recoveringServices || state.unsafePendingUpdate)
    }
}
