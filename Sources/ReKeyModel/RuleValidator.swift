import Foundation

public enum RuleValidator {
    private static let modifiers = Set(["left_control", "left_shift", "left_option", "left_command", "right_control", "right_shift", "right_option", "right_command", "control", "shift", "option", "command"])
    private static func object(_ value: JSONValue, fields: Set<String>, label: String) throws -> [String: JSONValue] {
        guard case .object(let o) = value else { throw ConfigError.invalid(String(format: L("%@ はオブジェクトで指定してください。"), label)) }
        let unsupported = Set(o.keys).subtracting(fields)
        guard unsupported.isEmpty else { throw ConfigError.invalid(String(format: L("%@: 未対応の項目 %@"), label, unsupported.sorted().joined(separator: ", "))) }
        return o
    }
    private static func strings(_ value: JSONValue?, label: String) throws -> [String] {
        guard let values = value?.array, values.allSatisfy({ $0.string != nil }) else { throw ConfigError.invalid(String(format: L("%@ は文字列の配列です。"), label)) }
        return values.compactMap(\.string)
    }
    private static func regex(_ pattern: String) throws { _ = try NSRegularExpression(pattern: pattern) }
    public static func validate(_ m: JSONValue) throws {
        let o = try object(m, fields: ["type", "from", "to", "to_if_alone", "to_if_held_down", "to_after_key_up", "conditions", "parameters"], label: "manipulator")
        guard o["type"]?.string == "basic", let from = o["from"] else { throw ConfigError.invalid(L("basic と from が必要です。")) }
        let f = try object(from, fields: ["key", "modifiers", "simultaneous", "any"], label: "from")
        guard ["key", "simultaneous", "any"].filter({ f[$0] != nil }).count == 1 else { throw ConfigError.invalid(L("from の key / simultaneous / any は 1 つだけ指定してください。")) }
        if let key = f["key"]?.string { try validateKey(key) }
        else if let chord = f["simultaneous"]?.array {
            guard (2...4).contains(chord.count) else { throw ConfigError.invalid(L("同時押しは 2〜4 キーです。")) }
            var keys: [String] = []
            for k in chord { let v = try object(k, fields: ["key"], label: "simultaneous"); guard let key = v["key"]?.string else { throw ConfigError.invalid(L("同時押しの key が必要です。")) }; try validateKey(key); keys.append(key) }
            guard Set(keys).count == keys.count else { throw ConfigError.invalid(L("同時押しキーが重複しています。")) }
        } else if f["any"]?.string != "key_code" { throw ConfigError.invalid(L("未対応の from です。")) }
        if let mods = f["modifiers"] {
            let mo = try object(mods, fields: ["mandatory", "optional"], label: "modifiers")
            for field in ["mandatory", "optional"] where mo[field] != nil {
                let v = try strings(mo[field], label: field)
                guard v.count <= 8, v.allSatisfy({ modifiers.contains($0) || (field == "optional" && $0 == "any") }) else { throw ConfigError.invalid(L("未対応の修飾キーです。")) }
            }
        }
        for field in ["to", "to_if_alone", "to_if_held_down", "to_after_key_up"] where o[field] != nil {
            guard let aa = o[field]?.array, aa.count <= 16 else { throw ConfigError.invalid(L("アクションは配列で、最大 16 個です。")) }
            for a in aa {
                let ac = try object(a, fields: ["key", "modifiers", "shell_command", "open_app", "select_input_source", "set_variable", "notify", "sticky_modifier", "layer"], label: field)
                let actionTypes = ["key", "shell_command", "open_app", "select_input_source", "set_variable", "notify", "sticky_modifier", "layer"].filter { ac[$0] != nil }
                guard actionTypes.count == 1 else { throw ConfigError.invalid(L("1 アクションに動作を 1 つ指定してください。")) }
                if let key = ac["key"]?.string { try validateKey(key) }
                if let mods = ac["modifiers"] { guard ac["key"] != nil, try strings(mods, label: "modifiers").allSatisfy({ modifiers.contains($0) }) else { throw ConfigError.invalid(L("出力の修飾キーが無効です。")) } }
                for field in ["shell_command", "open_app", "notify", "select_input_source"] where ac[field] != nil {
                    guard let text = ac[field]?.string, !text.isEmpty, text.utf8.count <= 8192 else { throw ConfigError.invalid(String(format: L("%@ は空でない文字列で指定してください。"), field)) }
                    if field == "select_input_source" { try regex(text) }
                }
                if let sticky = ac["sticky_modifier"] { guard let name = sticky.string, modifiers.contains(name), KeyCatalog.usages[name] != nil else { throw ConfigError.invalid(L("sticky_modifier は左右を指定した修飾キーです。")) } }
                if let variable = ac["set_variable"] {
                    let v = try object(variable, fields: ["name", "value"], label: "set_variable")
                    guard let name = v["name"]?.string, !name.isEmpty, case .number(let n) = v["value"], n.isFinite, n.rounded() == n, abs(n) <= Double(Int32.max) else { throw ConfigError.invalid(L("変数名と整数値が必要です。")) }
                }
                if let layer = ac["layer"] {
                    if let name = layer.string { guard !name.isEmpty else { throw ConfigError.invalid(L("レイヤー名が必要です。")) } }
                    else { let v = try object(layer, fields: ["name", "value"], label: "layer"); guard let name = v["name"]?.string, !name.isEmpty else { throw ConfigError.invalid(L("レイヤー名が必要です。")) }; if let value = v["value"], value != .number(0) && value != .number(1) { throw ConfigError.invalid(L("レイヤーの値は 0 または 1 です。")) } }
                }
            }
        }
        if let conditions = o["conditions"] {
            guard let cc = conditions.array else { throw ConfigError.invalid(L("conditions は配列です。")) }
            for c in cc {
                guard let type = c["type"]?.string else { throw ConfigError.invalid(L("条件の type が必要です。")) }
                switch type {
                case "frontmost_app_if", "frontmost_app_unless":
                    _ = try object(c, fields: ["type", "bundle_identifiers"], label: type)
                    for pattern in try strings(c["bundle_identifiers"], label: type) { try regex(pattern) }
                case "device_if", "device_unless":
                    _ = try object(c, fields: ["type", "identifiers"], label: type)
                    guard let ids = c["identifiers"]?.array else { throw ConfigError.invalid(L("identifiers が必要です。")) }
                    for id in ids { let v = try object(id, fields: ["vendor_id", "product_id", "serial"], label: type); guard case .number(let vendor) = v["vendor_id"], case .number(let product) = v["product_id"], (0...65535).contains(vendor), (0...65535).contains(product), vendor.rounded() == vendor, product.rounded() == product else { throw ConfigError.invalid(L("デバイスの vendor_id / product_id が必要です。")) } }
                case "input_source_if", "input_source_unless":
                    _ = try object(c, fields: ["type", "input_sources"], label: type)
                    guard let ss = c["input_sources"]?.array else { throw ConfigError.invalid(L("input_sources が必要です。")) }
                    for source in ss { let v = try object(source, fields: ["input_source_id"], label: type); guard let pattern = v["input_source_id"]?.string else { throw ConfigError.invalid(L("input_source_id が必要です。")) }; try regex(pattern) }
                case "keyboard_type_if", "keyboard_type_unless":
                    _ = try object(c, fields: ["type", "keyboard_types"], label: type)
                    guard try strings(c["keyboard_types"], label: type).allSatisfy({ ["ansi", "iso", "jis"].contains($0) }) else { throw ConfigError.invalid(L("キーボード種別が無効です。")) }
                case "variable_if", "variable_unless":
                    let v = try object(c, fields: ["type", "name", "value"], label: type)
                    guard let name = v["name"]?.string, !name.isEmpty, case .number(let n) = v["value"], n.rounded() == n, abs(n) <= Double(Int32.max) else { throw ConfigError.invalid(L("変数条件の name / value が必要です。")) }
                case "layer_if", "layer_unless":
                    _ = try object(c, fields: ["type", "name"], label: type)
                    guard let name = c["name"]?.string, !name.isEmpty else { throw ConfigError.invalid(L("レイヤー名が必要です。")) }
                default: throw ConfigError.invalid(String(format: L("未対応の条件: %@"), type))
                }
            }
        }
        if let parameters = o["parameters"] {
            let p = try object(parameters, fields: ["basic.to_if_alone_timeout_milliseconds", "basic.to_if_held_down_threshold_milliseconds", "basic.simultaneous_threshold_milliseconds"], label: "parameters")
            for (key, value) in p { guard case .number(let n) = value, n.rounded() == n, n >= 1, n <= (key.contains("simultaneous") ? 500 : 5000) else { throw ConfigError.invalid(L("判定時間が範囲外です。")) } }
        }
    }
    private static func validateKey(_ key: String) throws { guard KeyCatalog.names.contains(key) else { throw ConfigError.invalid(String(format: L("未対応のキー: %@"), key)) } }
}
