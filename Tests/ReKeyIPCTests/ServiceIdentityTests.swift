import Foundation
import Testing
@testable import ReKeyIPC

@Test func serviceIdentityUsesSharedProductIDInAppAndAgentBundles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReKey-identity-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    for suffix in ["app", "agent"] {
        let contents = root.appendingPathComponent("\(suffix).bundle/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": suffix == "app" ? "org.example.product" : "org.example.product.agent",
                                   "ReKeyProductIdentifier": "org.example.product"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: contents.deletingLastPathComponent()))
        #expect(ReKeyServiceIdentity.coreName(in: bundle) == "org.example.product.core")
        #expect(ReKeyServiceIdentity.agentName(in: bundle) == "org.example.product.agent")
        #expect(ReKeyServiceIdentity.permissionNotification(in: bundle) == "org.example.product.agent.request-permissions")
    }
}
