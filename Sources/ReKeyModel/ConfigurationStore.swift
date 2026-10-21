import Foundation

public struct ImportResult: Sendable {
    public var profiles: [Profile]
    public var warnings: [String]
    public init(profiles: [Profile], warnings: [String]) { self.profiles = profiles; self.warnings = warnings }
}
public enum KarabinerImporter {
    public static func read(_ data: Data) throws -> ImportResult {
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let profiles = root["profiles"]?.array else { throw ConfigError.invalid("Karabiner の profiles がありません。") }
        var result = ImportResult(profiles: [], warnings: [])
        func key(_ spec: JSONValue) -> JSONValue {
            guard case .object(var o) = spec else { return spec }
            if let k = o.removeValue(forKey: "key_code") { o["key"] = k }
            if let k = o.removeValue(forKey: "consumer_key_code") { o["key"] = k }
            return .object(o)
        }
        func manipulator(_ m: JSONValue, location: String) -> JSONValue? {
            guard m["type"]?.string == "basic" else { result.warnings.append("\(location): basic 以外の manipulator をスキップしました。"); return nil }
            guard case .object(var o) = m else { return nil }
            o["from"] = key(o["from"] ?? .object([:]))
            if var from = o["from"], let chord = from["simultaneous"]?.array { from["simultaneous"] = .array(chord.map(key)); o["from"] = from }
            for field in ["to", "to_if_alone", "to_if_held_down", "to_after_key_up"] {
                if let actions = o[field]?.array {
                    for a in actions where a["shell_command"] != nil { result.warnings.append("\(location): shell_command を含みます。内容を確認してから使用してください。") }
                    o[field] = .array(actions.map(key))
                }
            }
            let supported = Set(["type", "from", "to", "to_if_alone", "to_if_held_down", "to_after_key_up", "conditions", "parameters"])
            let unsupported = o.keys.filter { !supported.contains($0) }.sorted()
            if !unsupported.isEmpty { result.warnings.append("\(location): 非対応フィールド \(unsupported.joined(separator: ", "))。ルールをスキップしました。"); return nil }
            let resultManipulator = JSONValue.object(o)
            do { try RuleValidator.validate(resultManipulator) }
            catch { result.warnings.append("\(location): \(error.localizedDescription) ルールをスキップしました。"); return nil }
            return resultManipulator
        }
        func simple(_ value: JSONValue?, location: String) -> [SimpleMapping] {
            var mappings: [SimpleMapping] = []
            if let value, value.array == nil { result.warnings.append("\(location): 配列形式でない simple_modifications は非対応です。"); return [] }
            for item in value?.array ?? [] {
                let f = key(item["from"] ?? .null)["key"]?.string
                let targets = item["to"]?.array ?? (item["to"].map { [$0] } ?? [])
                if let f, let t = targets.first.map(key)?["key"]?.string, targets.count == 1, case .object(let fromObject) = key(item["from"] ?? .null), Set(fromObject.keys) == Set(["key"]), case .object(let toObject) = key(targets[0]), Set(toObject.keys) == Set(["key"]), KeyCatalog.names.contains(f), KeyCatalog.names.contains(t) {
                    mappings.append(.init(from: f, to: t))
                } else { result.warnings.append("\(location): 非対応の単純リマップをスキップしました。") }
            }
            return mappings
        }
        for (index, source) in profiles.enumerated() {
            var p = Profile(name: source["name"]?.string ?? "Imported \(index + 1)")
            p.selected = false
            p.simple = simple(source["simple_modifications"], location: p.name)
            for rule in source["complex_modifications"]?["rules"]?.array ?? [] {
                let name = rule["description"]?.string ?? "Imported rule"
                let ms = (rule["manipulators"]?.array ?? []).compactMap { manipulator($0, location: name) }
                if !ms.isEmpty { p.rules.append(.init(name: name, manipulators: ms)) }
            }
            for device in source["devices"]?.array ?? [] {
                guard case .number(let vendor) = device["identifiers"]?["vendor_id"], case .number(let product) = device["identifiers"]?["product_id"] else { result.warnings.append("\(p.name): 識別子のないデバイスをスキップしました。"); continue }
                var d = DeviceSettings(id: .init(vendor_id: Int(vendor), product_id: Int(product)))
                if case .bool(let ignore) = device["ignore"] { d.ignore = ignore }
                if case .bool(let disable) = device["disable_built_in_keyboard_if_exists"] { d.disable_builtin_when_connected = disable }
                d.simple = simple(device["simple_modifications"], location: d.id.label)
                p.devices.append(d)
            }
            if source["fn_function_keys"] != nil { result.warnings.append("\(p.name): fn_function_keys の個別指定はインポートしていません。") }
            result.profiles.append(p)
        }
        guard !result.profiles.isEmpty else { throw ConfigError.invalid("インポートできるプロファイルがありません。") }
        return result
    }
}
