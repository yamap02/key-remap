// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ReKey", platforms: [.macOS("27.0")], products: [
    .executable(name: "ReKey", targets: ["ReKeyApp"]),
    .library(name: "ReKeyModel", targets: ["ReKeyModel"]),
    .executable(name: "ReKeyAgent", targets: ["ReKeyAgent"])
], targets: [
    .target(name: "ReKeyValidation", path: "CoreValidation", publicHeadersPath: "include", cxxSettings: [.headerSearchPath("../Core"), .headerSearchPath("../Vendor/VirtualHID/vendor/vendor/include")]),
    .target(name: "ReKeyModel", dependencies: ["ReKeyValidation"]),
    .target(name: "ReKeyIPC"),
    .executableTarget(name: "ReKeyAgent", dependencies: ["ReKeyModel", "ReKeyIPC"]),
    .executableTarget(name: "ReKeyApp", dependencies: ["ReKeyModel", "ReKeyIPC"]),
    .testTarget(name: "ReKeyModelTests", dependencies: ["ReKeyModel"]),
    .testTarget(name: "ReKeyIPCTests", dependencies: ["ReKeyIPC"]),
    .testTarget(name: "ReKeyAppTests", dependencies: ["ReKeyApp"])
], swiftLanguageModes: [.v6], cxxLanguageStandard: .cxx2b)
