import Testing
import Foundation
@testable import ReKeyModel

private func temporaryStore() -> (URL, ConfigurationStore) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReKey-transaction-\(UUID().uuidString)")
    return (root, ConfigurationStore(url: root.appendingPathComponent("rekey.json")))
}
@Test func editorMergesAgentSelectionWithoutLosingMappings() throws {
    let (root, store) = temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
    var initial = Configuration(); var other = Profile(name: "Other"); other.selected = false; initial.profiles.append(other)
    try store.update { $0 = initial }
    let baseline = try store.snapshot()
    var draft = baseline.configuration; draft.profiles[0].simple.append(.init())
    try store.update { latest in latest.select(other.id); latest.global.paused = true }
    let merged = try store.save(draft, basedOn: baseline.data)
    #expect(merged.configuration.activeProfile.id == other.id)
    #expect(merged.configuration.global.paused)
    #expect(merged.configuration.profiles[0].simple.first?.from.key == "caps_lock")
    #expect(merged.warnings.isEmpty)
}
@Test func conflictingEditsKeepDiskAndDraftIntact() throws {
    let (root, store) = temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
    try store.update { $0 = .init() }; let baseline = try store.snapshot()
    var draft = baseline.configuration; draft.profiles[0].name = "Editor"
    try store.update { $0.profiles[0].name = "Other process" }
    let before = try Data(contentsOf: store.url)
    #expect(throws: ConfigurationConflict.self) { try store.save(draft, basedOn: baseline.data) }
    #expect(try Data(contentsOf: store.url) == before)
    #expect(draft.profiles[0].name == "Editor")
}
@Test func concurrentProfileSelectionsConflictAsOneChoice() throws {
    let (root, store) = temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
    var c = Configuration(); var b = Profile(name: "B"); b.selected = false; var d = Profile(name: "C"); d.selected = false; c.profiles += [b, d]
    try store.update { $0 = c }; let baseline = try store.snapshot()
    var draft = baseline.configuration; draft.select(b.id)
    try store.update { $0.select(d.id) }
    #expect(throws: ConfigurationConflict.self) { try store.save(draft, basedOn: baseline.data) }
    #expect(try store.load().activeProfile.id == d.id)
}
@Test func concurrentTransactionsLoseNoUpdates() async throws {
    let (root, store) = temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
    try store.update { $0 = .init() }
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<8 { group.addTask { for _ in 0..<4 { try store.update { $0.global.thresholds_ms.alone += 1 } } } }
        try await group.waitForAll()
    }
    #expect(try store.load().global.thresholds_ms.alone == 232)
    let backups = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
    #expect(backups.count == 20)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasSuffix(".tmp") })
}
@Test func retainedBackupsAreTheNewestGenerations() throws {
    let (root, store) = temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
    var c = Configuration(); try store.update { $0 = c }
    for n in 1...24 { c.profiles[0].name = "Version \(n)"; try store.update { $0 = c } }
    let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
    let names = try files.map { try Configuration.decode(Data(contentsOf: $0)).activeProfile.name }
    #expect(Set(names) == Set((4...23).map { "Version \($0)" }))
    for file in files { #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600) }
}
@Test func unchangedSavesDoNotWriteOrCreateBackups() throws {
    let (root, store) = temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
    try store.update { $0 = .init() }; let baseline = try store.snapshot()
    let before = try FileManager.default.attributesOfItem(atPath: store.url.path)[.modificationDate] as? Date
    let saved = try store.save(baseline.configuration, basedOn: baseline.data)
    #expect(saved.data == baseline.data)
    #expect(try FileManager.default.attributesOfItem(atPath: store.url.path)[.modificationDate] as? Date == before)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Backups").path))
}
@Test func newExternalFileIsNotOverwrittenByUnsavedWelcomeState() throws {
    let (root, store) = temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
    let fresh = try store.snapshot()
    var other = Configuration(); other.profiles[0].name = "External"; try store.update { $0 = other }
    #expect(throws: ConfigurationConflict.self) { try store.save(fresh.configuration, basedOn: fresh.data) }
    #expect(try store.load().activeProfile.name == "External")
}
@Test func unsafeFileAndLockModesAreRejected() throws {
    let (root, store) = temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
    try store.update { $0 = .init() }; try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.url.path)
    #expect(throws: (any Error).self) { try store.load() }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.url.path)
    let lock = root.appendingPathComponent(".rekey.json.lock")
    try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: lock.path)
    #expect(throws: (any Error).self) { try store.update { $0.global.paused = true } }
    #expect(try store.load().global.paused == false)
}
@Test func independentProfileAdditionsAndDiskOrderArePreserved() throws {
    let (root, store) = temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
    var initial = Configuration(); var b = Profile(name: "B"); b.selected = false; initial.profiles.append(b)
    try store.update { $0 = initial }; let baseline = try store.snapshot()
    var draft = baseline.configuration; draft.profiles[0].name = "Renamed"
    var added = Profile(name: "Added"); added.selected = false; draft.profiles.append(added)
    try store.update { $0.profiles.swapAt(0, 1) }
    let merged = try store.save(draft, basedOn: baseline.data).configuration
    #expect(merged.profiles.map(\.name) == ["B", "Renamed", "Added"])
}
@Test func editingADeletedProfileIsAConflict() throws {
    let (root, store) = temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
    var initial = Configuration(); var b = Profile(name: "B"); b.selected = false; initial.profiles.append(b)
    try store.update { $0 = initial }; let baseline = try store.snapshot()
    var draft = baseline.configuration; draft.profiles[1].name = "Edited"
    try store.update { $0.profiles.removeLast() }
    #expect(throws: ConfigurationConflict.self) { try store.save(draft, basedOn: baseline.data) }
    #expect(try store.load().profiles.count == 1)
}
@Test func canonicalAndSymlinkedWritersUseTheSameTransaction() throws {
    let (root, direct) = temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
    try direct.update { $0 = .init() }
    let alias = root.appendingPathComponent("linked.json")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: direct.url)
    let linked = ConfigurationStore(url: alias); let baseline = try linked.snapshot()
    var draft = baseline.configuration; draft.profiles[0].simple.append(.init())
    try direct.update { $0.global.paused = true }
    let merged = try linked.save(draft, basedOn: baseline.data)
    #expect(merged.configuration.global.paused)
    #expect(try direct.load().profiles[0].simple.count == 1)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path) == direct.url.path)
}
