import Testing
@testable import ReKeyModel

@Test func categorizedKeysCoverCatalogExactlyOnce() {
    let keys = KeyCatalog.Category.allCases.flatMap(\.keys)
    #expect(Set(keys) == Set(KeyCatalog.names))
    #expect(keys.count == Set(keys).count)
}

@Test func jisConversionKeysHaveDistinctHIDUsages() throws {
    let jis: [(String, UInt32)] = [("international1", 135), ("international2", 136), ("international3", 137), ("international4", 138), ("international5", 139), ("japanese_kana", 144), ("japanese_eisuu", 145)]
    var config = Configuration()
    config.profiles[0].simple = jis.map { .init(from: $0.0, to: "return_or_enter") }
    let decoded = try Configuration.decode(config.encoded())
    #expect(decoded.activeProfile.simple.map(\.from.key) == jis.map(\.0))
    for (name, usage) in jis {
        #expect(KeyCatalog.usages[name] == usage)
        #expect(KeyCatalog.name(page: 7, usage: usage) == name)
        #expect(KeyCatalog.Category.japanese.keys.contains(name))
    }
    #expect(KeyCatalog.label("international2").contains("ローマ字"))
    #expect(KeyCatalog.macKeyCodes[93] == "international3")
    #expect(KeyCatalog.macKeyCodes[94] == "international1")
    #expect(KeyCatalog.macKeyCodes[104] == "japanese_kana")
}
