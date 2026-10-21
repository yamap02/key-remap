import Testing
import Foundation
@testable import ReKeyModel

@Test func roundTripAndDeviceIsolation() throws {
    var c = Configuration()
    c.profiles[0].simple = [.init(from: "caps_lock", to: "left_control")]
    var device = DeviceSettings(id: .init(vendor_id: 1452, product_id: 641, serial: "one"))
    device.simple = [.init(from: "a", to: "b")]; device.layers = [.init()]; device.rules = [.init()]
    c.profiles[0].devices = [device]
    let decoded = try Configuration.decode(c.encoded())
    #expect(decoded.activeProfile.simple[0].from.key == "caps_lock")
    #expect(decoded.activeProfile.devices[0].simple[0].from.key == "a")
    #expect(decoded.activeProfile.devices[0].layers[0].map["h"] == "left_arrow")
}
@Test func rejectFutureAndInvalid() throws {
    var c = Configuration(); c.schema_version = 99
    #expect(throws: (any Error).self) { try c.encoded() }
    c.schema_version = 1; c.profiles = []
    #expect(throws: (any Error).self) { try c.encoded() }
    c = .init(); c.profiles[0].simple = [.init(from: "unknown", to: "a")]
    #expect(throws: (any Error).self) { try c.encoded() }
}
@Test func atomicPrivateStorageAndRetention() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ConfigurationStore(url: root.appendingPathComponent("rekey.json"))
    for i in 0..<24 { var c = Configuration(); c.profiles[0].name = "Profile \(i)"; try store.save(c) }
    #expect(try store.load().activeProfile.name == "Profile 23")
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Backups").path).count == 20)
    let attrs = try FileManager.default.attributesOfItem(atPath: store.url.path)
    #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}
@Test func symlinkRemainsIntact() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let target = root.appendingPathComponent("cloud.json"), link = root.appendingPathComponent("rekey.json")
    try ConfigurationStore(url: target).save(.init())
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    var c = Configuration(); c.profiles[0].name = "Cloud"
    try ConfigurationStore(url: link).save(c)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    #expect(try ConfigurationStore(url: target).load().activeProfile.name == "Cloud")
}
@Test func importKarabinerWithWarnings() throws {
    let data = Data(#"{"profiles":[{"name":"Work","simple_modifications":[{"from":{"key_code":"caps_lock"},"to":[{"key_code":"left_control"}]}],"complex_modifications":{"rules":[{"description":"tap","manipulators":[{"type":"basic","from":{"key_code":"a"},"to_if_alone":[{"key_code":"escape"}]},{"type":"mouse_motion_to_scroll"}]}]}}]}"#.utf8)
    let imported = try KarabinerImporter.read(data)
    #expect(imported.profiles[0].simple[0].to[0].key == "left_control")
    #expect(imported.profiles[0].rules[0].manipulators[0]["from"]?["key"]?.string == "a")
    #expect(imported.warnings.count == 1)
}
@Test func advancedRulesRejectSilentLoss() throws {
    let bad = [
        #"{"type":"basic","from":{"key":"a"},"to":[{"key":"b","repeat":false}]}"#,
        #"{"type":"basic","from":{"simultaneous":[{"key":"a"},{"key":"a"}]},"to":[]}"#,
        #"{"type":"basic","from":{"key":"a"},"conditions":[{"type":"event_changed_if"}]}"#,
        #"{"type":"basic","from":{"key":"a"},"to":[{"key":"b","shell_command":"true"}]}"#,
        #"{"type":"basic","from":{"key":"a"},"parameters":{"basic.simultaneous_threshold_milliseconds":0}}"#
    ]
    for text in bad {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(throws: (any Error).self) { try RuleValidator.validate(value) }
    }
    let good = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"basic","from":{"key":"a","modifiers":{"mandatory":["command"],"optional":["any"]}},"to":[{"set_variable":{"name":"nav","value":1}},{"shell_command":"true"}],"conditions":[{"type":"input_source_if","input_sources":[{"input_source_id":"^com\\.apple"}]}]}"#.utf8))
    try RuleValidator.validate(good)
}
@Test func importerWarnsInsteadOfDroppingActionFlags() throws {
    let text = #"{"profiles":[{"name":"Test","complex_modifications":{"rules":[{"description":"unsupported","manipulators":[{"type":"basic","from":{"key_code":"a"},"to":[{"key_code":"b","repeat":false}]}]}]}}]}"#
    let result = try KarabinerImporter.read(Data(text.utf8))
    #expect(result.profiles[0].rules.isEmpty)
    #expect(result.warnings.count == 1)
}
@Test func sharedCompilerRejectsUnresolvableRulesBeforeSaving() throws {
    var config = Configuration()
    let missingLayer = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"basic","from":{"key":"a"},"to":[{"layer":"missing"}]}"#.utf8))
    config.profiles[0].rules = [.init(name: "missing layer", manipulators: [missingLayer])]
    #expect(throws: (any Error).self) { try config.encoded() }
    let unsupportedRegex = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"basic","from":{"key":"a"},"to":[{"key":"b"}],"conditions":[{"type":"frontmost_app_if","bundle_identifiers":["(?<=a)b"]}]}"#.utf8))
    config.profiles[0].rules = [.init(name: "regex", manipulators: [unsupportedRegex])]
    #expect(throws: (any Error).self) { try config.encoded() }
}
@Test func invalidEditsLeavePersistedSettingsUntouched() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ConfigurationStore(url: root.appendingPathComponent("rekey.json"))
    try store.save(.init())
    let valid = try Data(contentsOf: store.url)
    var bad = Configuration(); bad.profiles[0].simple = [.init(from: "not_a_key", to: "a")]
    #expect(throws: (any Error).self) { try store.save(bad) }
    #expect(try Data(contentsOf: store.url) == valid)
}
