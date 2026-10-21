import Testing
@testable import ReKeyModel

@Test func categorizedKeysCoverCatalogExactlyOnce() {
    let keys = KeyCatalog.Category.allCases.flatMap(\.keys)
    #expect(Set(keys) == Set(KeyCatalog.names))
    #expect(keys.count == Set(keys).count)
}
