import SwiftUI
import ReKeyModel

struct ComplexRulesView: View {
    @ObservedObject var state: AppState
    @State private var editing: ComplexRule?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("組み合わせ、単押し、長押しをひとつのルールに。").foregroundStyle(.secondary)
            ScopePicker(state: state)
            if state.complexRules.isEmpty {
                ContentUnavailableView { Label("複合ルール", systemImage: "point.3.connected.trianglepath.dotted") } description: { Text("Caps Lock は長押しで Control、単押しで Escape。\n条件とアクションを組み合わせて設定できます。") } actions: { Button("ルールを作成", systemImage: "plus") { editing = .init() }.buttonStyle(.borderedProminent) }
            } else {
                List {
                    ForEach(Array(state.complexRules.enumerated()), id: \.element.id) { index, rule in
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1)).monospacedDigit().foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 5) { Text(rule.name).fontWeight(.medium); Text("\(rule.manipulators.count) manipulators").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button { if index > 0 { state.complexRules.swapAt(index, index - 1) } } label: { Image(systemName: "chevron.up") }.disabled(index == 0).help("上へ移動")
                            Button { if index + 1 < state.complexRules.count { state.complexRules.swapAt(index, index + 1) } } label: { Image(systemName: "chevron.down") }.disabled(index == state.complexRules.count - 1).help("下へ移動")
                            Button("編集") { editing = rule }
                            Button(role: .destructive) { state.complexRules.remove(at: index) } label: { Image(systemName: "trash") }.help("削除")
                        }.padding(.vertical, 10)
                    }
                }.listStyle(.inset).clipShape(RoundedRectangle(cornerRadius: 12))
                Button("ルールを追加", systemImage: "plus") { editing = .init() }
            }
            Label("上から順に評価し、最初に一致したルールを適用します。", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 28).padding(.bottom, 24)
        .sheet(item: $editing) { rule in RuleEditor(rule: rule, validation: { candidate in
            var list = state.complexRules
            if let i = list.firstIndex(where: { $0.id == candidate.id }) { list[i] = candidate } else { list.append(candidate) }
            try state.validate(rules: list)
        }) { updated in
            if let i = state.complexRules.firstIndex(where: { $0.id == updated.id }) { state.complexRules[i] = updated } else { state.complexRules.append(updated) }
        } }
    }
}
struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: ComplexRule
    var validation: (ComplexRule) throws -> Void
    var onSave: (ComplexRule) -> Void
    @State private var mode = "form"
    @State private var json = ""
    @State private var error: String?
    @State private var from = "caps_lock"
    @State private var to = "left_control"
    @State private var alone = "escape"
    @State private var held = "left_control"
    @State private var after = "escape"
    @State private var useAlone = true
    @State private var useHeld = false
    @State private var useAfter = false
    @State private var app = ""
    @State private var mandatory = ""
    @State private var advancedExisting = false
    /// Last value handed to onSave (initially the opened rule), so opening the editor saves nothing.
    @State private var saved: ComplexRule?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("複合ルールを編集").font(.title2.bold())
            TextField("ルール名", text: $rule.name).textFieldStyle(.roundedBorder)
            Picker("編集形式", selection: $mode) { Text("フォーム").tag("form"); Text("JSON").tag("json") }.pickerStyle(.segmented)
                .onChange(of: mode) { old, new in
                    if old == "form" && new == "json" { encodeForm() }
                    if old == "json" && new == "form" { decodeJSON() }
                }
            if mode == "json" {
                TextEditor(text: $json).font(.system(.body, design: .monospaced)).scrollContentBackground(.hidden).padding(8).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                Text("同時押し、複数アクション、変数・入力ソース・デバイス条件は JSON で編集できます。").font(.caption).foregroundStyle(.secondary)
            } else if advancedExisting {
                ContentUnavailableView("このルールは JSON で編集できます", systemImage: "curlybraces", description: Text("複数の manipulator や高度な条件を保持するため、JSON タブを使用してください。"))
            } else {
                Form {
                    Section("入力と出力") {
                        KeyPicker(title: "入力キー", selection: $from)
                        KeyPicker(title: "出力キー", selection: $to)
                        TextField("必須修飾キー（カンマ区切り）", text: $mandatory)
                    }
                    Section("押し方による動作") {
                        Toggle("単押し時", isOn: $useAlone)
                        if useAlone { KeyPicker(title: "単押しの出力", selection: $alone) }
                        Toggle("長押し時", isOn: $useHeld)
                        if useHeld { KeyPicker(title: "長押しの出力", selection: $held) }
                        Toggle("キーを離した後", isOn: $useAfter)
                        if useAfter { KeyPicker(title: "離した後の出力", selection: $after) }
                    }
                    Section("条件") { TextField("アプリの bundle ID（正規表現・空欄で全アプリ）", text: $app) }
                }.formStyle(.grouped)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer(); Button("閉じる") { dismiss() }
                Text("有効な変更を自動保存").font(.caption).foregroundStyle(.secondary)

            }
        }.padding(24).frame(width: 640, height: 640)
        .onAppear { initialize() }
        .onChange(of: json) { persist() }
        .onChange(of: rule.name) { persist() }
        // encodeForm が json を変えると onChange(of: json) が persist する。
        .onChange(of: formSnapshot) { if mode == "form" && !advancedExisting { encodeForm() } }

    }
    var formSnapshot: [String] { [from, to, alone, held, after, String(useAlone), String(useHeld), String(useAfter), app, mandatory] }
    func persist() {
        guard !json.isEmpty else { return }
        do {
            let parsed = try JSONDecoder().decode([JSONValue].self, from: Data(json.utf8))
            var candidate = rule; candidate.manipulators = parsed
            guard candidate != saved else { error = nil; return }
            try validation(candidate)
            onSave(candidate); saved = candidate; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func initialize() {
        saved = rule
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        json = (try? String(data: enc.encode(rule.manipulators), encoding: .utf8)) ?? "[]"
        decodeJSON()
        if advancedExisting { mode = "json" }
    }
    func decodeJSON() {
        do {
            let ms = try JSONDecoder().decode([JSONValue].self, from: Data(json.utf8))
            guard let m = ms.first else { advancedExisting = true; return }
            rule.manipulators = ms
            let supportedKeys = Set(["type", "from", "to", "to_if_alone", "to_if_held_down", "to_after_key_up", "conditions"])
            var advanced = ms.count != 1 || m["from"]?["key"]?.string == nil || m["to"] == nil
            if case .object(let o) = m, !Set(o.keys).isSubset(of: supportedKeys) { advanced = true }
            if case .object(let f) = m["from"], !Set(f.keys).isSubset(of: Set(["key", "modifiers"])) { advanced = true }
            for k in ["to", "to_if_alone", "to_if_held_down", "to_after_key_up"] {
                if let aa = m[k]?.array, aa.count != 1 || aa.first?["key"]?.string == nil { advanced = true }
                if let aa = m[k]?.array { for a in aa { if case .object(let o) = a, Set(o.keys) != Set(["key"]) { advanced = true } } }
            }
            if let conditions = m["conditions"]?.array, !conditions.isEmpty {
                if conditions.count == 1, conditions[0]["type"]?.string == "frontmost_app_if", let patterns = conditions[0]["bundle_identifiers"]?.array, patterns.count == 1 { app = patterns[0].string ?? "" } else { advanced = true }
            }
            if let optional = m["from"]?["modifiers"]?["optional"]?.array, !optional.isEmpty { advanced = true }
            advancedExisting = advanced
            from = m["from"]?["key"]?.string ?? "caps_lock"
            to = m["to"]?.array?.first?["key"]?.string ?? "left_control"
            mandatory = (m["from"]?["modifiers"]?["mandatory"]?.array ?? []).compactMap(\.string).joined(separator: ", ")
            useAlone = m["to_if_alone"] != nil; alone = m["to_if_alone"]?.array?.first?["key"]?.string ?? "escape"
            useHeld = m["to_if_held_down"] != nil; held = m["to_if_held_down"]?.array?.first?["key"]?.string ?? "left_control"
            useAfter = m["to_after_key_up"] != nil; after = m["to_after_key_up"]?.array?.first?["key"]?.string ?? "escape"
            error = nil
        } catch { self.error = error.localizedDescription; advancedExisting = true; mode = "json" }
    }
    func encodeForm() {
        guard !advancedExisting else { return }
        var f: [String: JSONValue] = ["key": .string(from)]
        let mods = mandatory.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !mods.isEmpty { f["modifiers"] = .object(["mandatory": .array(mods.map(JSONValue.string))]) }
        func action(_ key: String) -> JSONValue { .array([.object(["key": .string(key)])]) }
        var m: [String: JSONValue] = ["type": .string("basic"), "from": .object(f), "to": action(to)]
        if useAlone { m["to_if_alone"] = action(alone) }; if useHeld { m["to_if_held_down"] = action(held) }; if useAfter { m["to_after_key_up"] = action(after) }
        if !app.isEmpty { m["conditions"] = .array([.object(["type": .string("frontmost_app_if"), "bundle_identifiers": .array([.string(app)])])]) }
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        json = (try? String(data: e.encode([JSONValue.object(m)]), encoding: .utf8)) ?? "[]"
    }
}
struct LayersView: View {
    @ObservedObject var state: AppState
    @State private var editing: Layer?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ひとつのキーボードに、もうひとつの配列を。").foregroundStyle(.secondary)
            ScopePicker(state: state)
            if state.layers.isEmpty {
                ContentUnavailableView { Label("レイヤーを作成", systemImage: "square.3.layers.3d") } description: { Text("Space を押しながら H・J・K・L で移動。\n押している間の切り替えと、トグルを選べます。") } actions: { Button("Navigation レイヤーを追加", systemImage: "plus") { editing = .init() }.buttonStyle(.borderedProminent) }
            } else {
                List {
                    ForEach(state.layers) { layer in
                        HStack(spacing: 16) {
                            Image(systemName: "square.3.layers.3d").font(.title2).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 5) { Text(layer.name).bold(); Text("\(KeyCatalog.label(layer.trigger.key)) · \(L(layer.mode == "hold" ? "押している間" : "トグル")) · \(layer.map.count) キー").font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Button("編集") { editing = layer }
                            Button(role: .destructive) { state.layers.removeAll { $0.id == layer.id } } label: { Image(systemName: "trash") }
                        }.padding(.vertical, 12)
                    }
                }.listStyle(.inset)
                Button("レイヤーを追加", systemImage: "plus") { editing = .init() }
            }
        }.padding(.horizontal, 28).padding(.bottom, 24)
        .sheet(item: $editing) { layer in LayerEditor(layer: layer, existingNames: Set(state.layers.filter { $0.id != layer.id }.map(\.name)), validation: { candidate in
            var list = state.layers
            if let i = list.firstIndex(where: { $0.id == candidate.id }) { list[i] = candidate } else { list.append(candidate) }
            try state.validate(layers: list)
        }) { result in
            if let i = state.layers.firstIndex(where: { $0.id == result.id }) { state.layers[i] = result } else { state.layers.append(result) }
        } }
    }
}
struct LayerEditor: View {
    @State var layer: Layer
    var existingNames: Set<String>
    var validation: (Layer) throws -> Void
    var onSave: (Layer) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [SimpleMapping] = []
    @State private var error: String?
    /// Last value handed to onSave (initially the opened layer), so opening the editor saves nothing.
    @State private var saved: Layer?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("レイヤーを編集").font(.title2.bold())
            TextField("レイヤー名", text: $layer.name).textFieldStyle(.roundedBorder)
            HStack { Text("起動キー"); KeyPicker(title: "起動キー", selection: $layer.trigger.key) }
            Picker("動作", selection: $layer.mode) { Text("押している間").tag("hold"); Text("トグル").tag("toggle") }.pickerStyle(.segmented)
            ScrollView {
                ForEach($rows) { $row in HStack { KeyPicker(title: "変更前", selection: $row.from.key); Image(systemName: "arrow.right").foregroundStyle(.secondary); KeyPicker(title: "変更後", selection: Binding(get: { row.to[0].key }, set: { row.to = [.init($0)] })); Button { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") } }.padding(.vertical, 5) }
            }
            Button("キーを追加", systemImage: "plus") { rows.append(.init(from: "a", to: "b")) }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack { Text("有効な変更を自動保存").font(.caption).foregroundStyle(.secondary); Spacer(); Button("閉じる") { dismiss() } }
        }.padding(24).frame(width: 600, height: 540)
        .onAppear { saved = layer; rows = layer.map.sorted { $0.key < $1.key }.map { .init(from: $0.key, to: $0.value) } }
        .onChange(of: rows) { persist() }
        .onChange(of: layer.name) { persist() }
        .onChange(of: layer.trigger) { persist() }
        .onChange(of: layer.mode) { persist() }
    }
    func persist() {
        guard Set(rows.map { $0.from.key }).count == rows.count, !layer.name.isEmpty, !existingNames.contains(layer.name) else { error = L("レイヤー名と入力キーを重複しないように指定してください。"); return }
        var candidate = layer
        candidate.map = Dictionary(uniqueKeysWithValues: rows.map { ($0.from.key, $0.to[0].key) })
        guard candidate != saved else { error = nil; return }
        do { try validation(candidate); onSave(candidate); saved = candidate; error = nil }
        catch { self.error = error.localizedDescription }

    }
}
