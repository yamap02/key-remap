import Foundation
import ReKeyValidation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue? {
        get { if case .object(let o) = self { return o[key] }; return nil }
        set { if case .object(var o) = self { o[key] = newValue; self = .object(o) } }
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
}

public struct Thresholds: Codable, Equatable, Sendable {
    public var alone = 200
    public var held_down = 500
    public var simultaneous = 50
    public init() {}
}
public struct GlobalSettings: Codable, Equatable, Sendable {
    public var check_for_updates = true
    public var show_in_menu_bar = true
    public var disable_on_quit = true
    public var thresholds_ms = Thresholds()
    public var start_at_login = true
    public var paused = false
    public init() {}
    enum CodingKeys: String, CodingKey { case check_for_updates, show_in_menu_bar, disable_on_quit, thresholds_ms, start_at_login, paused }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        check_for_updates = try c.decodeIfPresent(Bool.self, forKey: .check_for_updates) ?? true
        show_in_menu_bar = try c.decodeIfPresent(Bool.self, forKey: .show_in_menu_bar) ?? true
        disable_on_quit = try c.decodeIfPresent(Bool.self, forKey: .disable_on_quit) ?? true
        thresholds_ms = try c.decodeIfPresent(Thresholds.self, forKey: .thresholds_ms) ?? .init()
        start_at_login = try c.decodeIfPresent(Bool.self, forKey: .start_at_login) ?? true
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
    }
}
public struct KeySpec: Codable, Equatable, Sendable {
    public var key: String
    public init(_ key: String) { self.key = key }
}
public struct SimpleMapping: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var from: KeySpec
    public var to: [KeySpec]
    public init(from: String = "caps_lock", to: String = "left_control") { self.from = .init(from); self.to = [.init(to)] }
    enum CodingKeys: String, CodingKey { case id, from, to }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        from = try c.decode(KeySpec.self, forKey: .from)
        to = try c.decode([KeySpec].self, forKey: .to)
    }
}
public struct Layer: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name = "Navigation"
    public var trigger = KeySpec("spacebar")
    public var mode = "hold"
    public var map = ["h": "left_arrow", "j": "down_arrow", "k": "up_arrow", "l": "right_arrow"]
    public init() {}
    enum CodingKeys: String, CodingKey { case id, name, trigger, mode, map }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        trigger = try c.decode(KeySpec.self, forKey: .trigger)
        mode = try c.decode(String.self, forKey: .mode)
        map = try c.decode([String: String].self, forKey: .map)
    }
}
public struct ComplexRule: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var manipulators: [JSONValue]
    public init(name: String = "Caps Lock: Control / Escape", manipulators: [JSONValue]? = nil) {
        self.name = name
        self.manipulators = manipulators ?? [.object([
            "type": .string("basic"), "from": .object(["key": .string("caps_lock")]),
            "to": .array([.object(["key": .string("left_control")])]),
            "to_if_alone": .array([.object(["key": .string("escape")])])
        ])]
    }
    enum CodingKeys: String, CodingKey { case id, name, manipulators }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        manipulators = try c.decode([JSONValue].self, forKey: .manipulators)
    }
}
public struct DeviceID: Codable, Equatable, Hashable, Sendable {
    public var vendor_id: Int
    public var product_id: Int
    public var serial: String?
    public init(vendor_id: Int, product_id: Int, serial: String? = nil) {
        self.vendor_id = vendor_id; self.product_id = product_id; self.serial = serial
    }
    public var label: String { "\(vendor_id):\(product_id)" + (serial.map { ":\($0)" } ?? "") }
}
public struct DeviceSettings: Codable, Identifiable, Equatable, Sendable {
    public var id: DeviceID
    public var ignore = false
    public var disable_builtin_when_connected = false
    public var fn_keys_as_media = true
    public var keyboard_type = "auto"
    public var simple: [SimpleMapping] = []
    public var layers: [Layer] = []
    public var rules: [ComplexRule] = []
    public init(id: DeviceID) { self.id = id }
    enum CodingKeys: String, CodingKey { case id, ignore, disable_builtin_when_connected, fn_keys_as_media, keyboard_type, simple, layers, rules }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(DeviceID.self, forKey: .id)
        ignore = try c.decodeIfPresent(Bool.self, forKey: .ignore) ?? false
        disable_builtin_when_connected = try c.decodeIfPresent(Bool.self, forKey: .disable_builtin_when_connected) ?? false
        keyboard_type = try c.decodeIfPresent(String.self, forKey: .keyboard_type) ?? "auto"
        fn_keys_as_media = try c.decodeIfPresent(Bool.self, forKey: .fn_keys_as_media) ?? true
        simple = try c.decodeIfPresent([SimpleMapping].self, forKey: .simple) ?? []
        layers = try c.decodeIfPresent([Layer].self, forKey: .layers) ?? []
        rules = try c.decodeIfPresent([ComplexRule].self, forKey: .rules) ?? []
    }
}
public struct AutoSelect: Codable, Equatable, Sendable {
    public var frontmost_app: [String] = []
    public var device: [DeviceID] = []
    public init() {}
}
public struct Shortcut: Codable, Equatable, Sendable {
    public var key = "1"
    public var modifiers = ["control", "option", "command"]
    public init() {}
}
public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var name = "Default"
    public var selected = true
    public var auto_select = AutoSelect()
    public var shortcut: Shortcut?
    public var simple: [SimpleMapping] = []
    public var layers: [Layer] = []
    public var rules: [ComplexRule] = []
    public var devices: [DeviceSettings] = []
    public init(name: String = "Default") { self.name = name }
    enum CodingKeys: String, CodingKey { case id, name, selected, auto_select, shortcut, simple, layers, rules, devices }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        selected = try c.decodeIfPresent(Bool.self, forKey: .selected) ?? false
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut)
        auto_select = try c.decodeIfPresent(AutoSelect.self, forKey: .auto_select) ?? .init()
        simple = try c.decodeIfPresent([SimpleMapping].self, forKey: .simple) ?? []
        layers = try c.decodeIfPresent([Layer].self, forKey: .layers) ?? []
        rules = try c.decodeIfPresent([ComplexRule].self, forKey: .rules) ?? []
        devices = try c.decodeIfPresent([DeviceSettings].self, forKey: .devices) ?? []
    }
}
public struct Configuration: Codable, Equatable, Sendable {
    public var schema_version = 1
    public var global = GlobalSettings()
    public var profiles = [Profile()]
    public init() {}
    public var activeProfile: Profile { profiles.first(where: \.selected) ?? profiles[0] }
    public mutating func select(_ id: String) { for i in profiles.indices { profiles[i].selected = profiles[i].id == id } }
    public func validated() throws -> Configuration { _ = try encoded(); return self }
    /// Validates once and returns the canonical bytes that the C++ validator also checked.
    public func encoded() throws -> Data {
        guard schema_version == 1 else { throw ConfigError.invalid("対応していない schema_version: \(schema_version)") }
        guard !profiles.isEmpty else { throw ConfigError.invalid("プロファイルは最低 1 つ必要です。") }
        guard Set(profiles.map(\.id)).count == profiles.count else { throw ConfigError.invalid("プロファイル ID が重複しています。") }
        guard profiles.filter(\.selected).count == 1 else { throw ConfigError.invalid("選択されたプロファイルは 1 つ必要です。") }
        let t = global.thresholds_ms
        guard (1...5000).contains(t.alone), (1...5000).contains(t.held_down), (1...500).contains(t.simultaneous) else { throw ConfigError.invalid("判定閾値が範囲外です。") }
        for p in profiles {
            if let shortcut = p.shortcut {
                guard KeyCatalog.macKeyCodes.values.contains(shortcut.key), !shortcut.modifiers.isEmpty, shortcut.modifiers.allSatisfy({ ["control", "option", "shift", "command"].contains($0) }), !shortcut.key.contains("command"), !shortcut.key.contains("control"), !shortcut.key.contains("shift"), !shortcut.key.contains("option") else { throw ConfigError.invalid("プロファイルのショートカットが無効です。") }
            }
            try Self.validate(simple: p.simple, layers: p.layers, rules: p.rules)
            for d in p.devices { guard ["auto", "ansi", "iso", "jis"].contains(d.keyboard_type) else { throw ConfigError.invalid("キーボード種別が無効です。") }; try Self.validate(simple: d.simple, layers: d.layers, rules: d.rules) }
            for pattern in p.auto_select.frontmost_app { _ = try NSRegularExpression(pattern: pattern) }
        }
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try e.encode(self); data.append(10)
        var message = [CChar](repeating: 0, count: 2048)
        let valid = data.withUnsafeBytes { bytes in rekey_validate_json(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &message, message.count) }
        guard valid == 1 else { throw ConfigError.invalid(String(decoding: message.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)) }
        return data
    }
    private static func validate(simple: [SimpleMapping], layers: [Layer], rules: [ComplexRule]) throws {
        for s in simple {
            guard KeyCatalog.names.contains(s.from.key), s.to.count == 1, s.to.allSatisfy({ KeyCatalog.names.contains($0.key) }) else { throw ConfigError.invalid("単純リマップに未対応のキーがあります。") }
        }
        guard Set(layers.map(\.name)).count == layers.count else { throw ConfigError.invalid("レイヤー名が重複しています。") }
        for l in layers {
            guard !l.name.isEmpty, ["hold", "toggle"].contains(l.mode), KeyCatalog.names.contains(l.trigger.key), l.map.allSatisfy({ KeyCatalog.names.contains($0.key) && KeyCatalog.names.contains($0.value) }) else { throw ConfigError.invalid("レイヤーの設定が無効です。") }
        }
        for r in rules {
            guard !r.manipulators.isEmpty else { throw ConfigError.invalid("ルールに manipulator が必要です。") }
            for m in r.manipulators {
                try RuleValidator.validate(m)
            }
        }
    }
    public static func decode(_ data: Data) throws -> Configuration { try JSONDecoder().decode(Self.self, from: data).validated() }
}
public enum ConfigError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let s): return s } }
}
