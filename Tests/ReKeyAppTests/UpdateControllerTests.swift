import Foundation
import Sparkle
import Testing
import ObjectiveC.runtime
@testable import ReKeyApp

@Test @MainActor func sparkleDefersInstallationUntilPreparationCompletes() async throws {
    var continuation: CheckedContinuation<Void, Never>?
    var installed = false
    var failed = false
    let controller = UpdateController(automaticChecks: false, prepare: {
        await withCheckedContinuation { continuation = $0 }
    }, preparationFailed: { _ in failed = true })
    let sparkle = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    let selector = NSSelectorFromString("updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:")
    #expect(controller.responds(to: selector))
    #expect(controller.updater(sparkle.updater, shouldPostponeRelaunchForUpdate: .empty(), untilInvoking: { installed = true }))
    for _ in 0..<100 where continuation == nil { try await Task.sleep(for: .milliseconds(1)) }
    let resume = try #require(continuation)
    #expect(!installed)
    resume.resume()
    for _ in 0..<100 where !installed { try await Task.sleep(for: .milliseconds(1)) }
    #expect(installed)
    #expect(!failed)
}

@Test @MainActor func sparkleAbortDuringPreparationDoesNotInstall() async throws {
    var continuation: CheckedContinuation<Void, Never>?
    var installed = false
    var aborts = 0
    let controller = UpdateController(automaticChecks: false, prepare: {
        await withCheckedContinuation { continuation = $0 }
    }, aborted: { _ in aborts += 1 })
    let sparkle = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    #expect(controller.updater(sparkle.updater, shouldPostponeRelaunchForUpdate: .empty(), untilInvoking: { installed = true }))
    for _ in 0..<100 where continuation == nil { try await Task.sleep(for: .milliseconds(1)) }
    let resume = try #require(continuation)
    #expect(controller.responds(to: NSSelectorFromString("updater:didAbortWithError:")))
    controller.updater(sparkle.updater, didAbortWithError: NSError(domain: "test", code: 1))
    resume.resume()
    for _ in 0..<100 where aborts < 2 { try await Task.sleep(for: .milliseconds(1)) }
    #expect(!installed)
    #expect(aborts == 2) // Once immediately, and again after the outstanding stop finishes.
}

@Test @MainActor func sparkleDoesNotInstallWhenPreparationFails() async throws {
    var installed = false
    var failed = false
    let controller = UpdateController(automaticChecks: false, prepare: {
        throw NSError(domain: "test", code: 1)
    }, pendingInstallFailed: { _ in failed = true })
    let sparkle = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    #expect(controller.updater(sparkle.updater, shouldPostponeRelaunchForUpdate: .empty(), untilInvoking: { installed = true }))
    for _ in 0..<100 where !failed { try await Task.sleep(for: .milliseconds(1)) }
    #expect(failed)
    #expect(!installed)
}

@Test @MainActor func installChoiceWaitsForServicesBeforeSparkleCanStageUpdate() async throws {
    var continuation: CheckedContinuation<Void, Never>?
    var choice: SPUUserUpdateChoice?
    let controller = UpdateController(automaticChecks: false, prepare: {
        await withCheckedContinuation { continuation = $0 }
    })
    controller.handleUpdateChoice(.install) { choice = $0 }
    for _ in 0..<100 where continuation == nil { try await Task.sleep(for: .milliseconds(1)) }
    let resume = try #require(continuation)
    #expect(choice == nil)
    resume.resume()
    for _ in 0..<100 where choice == nil { try await Task.sleep(for: .milliseconds(1)) }
    #expect(choice == .install)
    #expect(controller.responds(to: NSSelectorFromString("updater:didFinishUpdateCycleForUpdateCheck:error:")))
}

@Test @MainActor func failedPreparationCancelsBeforeRestoringServices() async throws {
    var choice: SPUUserUpdateChoice?
    var failed = false
    let controller = UpdateController(automaticChecks: false, prepare: {
        throw NSError(domain: "test", code: 1)
    }, preparationFailed: { _ in failed = true })
    let sparkle = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    controller.handleUpdateChoice(.install) { choice = $0 }
    for _ in 0..<100 where choice == nil { try await Task.sleep(for: .milliseconds(1)) }
    #expect(choice == .skip)
    #expect(!failed)
    controller.updater(sparkle.updater, didAbortWithError: NSError(domain: "test", code: 1))
    #expect(!failed)
    controller.updater(sparkle.updater, didFinishUpdateCycleFor: .updates, error: nil)
    #expect(failed)
}

@Test @MainActor func dismissingAnUpdateDoesNotStopServices() {
    var prepared = false
    var choice: SPUUserUpdateChoice?
    let controller = UpdateController(automaticChecks: false, prepare: { prepared = true })
    controller.handleUpdateChoice(.dismiss) { choice = $0 }
    #expect(choice == .dismiss)
    #expect(!prepared)
}

@Test @MainActor func customDriverOverridesSparkleChoiceCallbacks() throws {
    for name in ["showUpdateFoundWithAppcastItem:state:reply:", "showReadyToInstallAndRelaunch:"] {
        let selector = NSSelectorFromString(name)
        let custom = try #require(class_getInstanceMethod(PreparingUserDriver.self, selector))
        let standard = try #require(class_getInstanceMethod(SPUStandardUserDriver.self, selector))
        let customImplementation = unsafeBitCast(method_getImplementation(custom), to: UInt.self)
        let standardImplementation = unsafeBitCast(method_getImplementation(standard), to: UInt.self)
        #expect(customImplementation != standardImplementation)
    }
}

@Test @MainActor func skippingWaitsForSparkleCycleToFinishBeforeRecovery() {
    var replies: [SPUUserUpdateChoice] = []
    var recovered = false
    let controller = UpdateController(automaticChecks: false, aborted: { _ in recovered = true })
    let sparkle = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    controller.handleUpdateChoice(.skip) { replies.append($0) }
    #expect(replies == [.skip])
    #expect(!recovered)
    controller.updater(sparkle.updater, didFinishUpdateCycleFor: .updates, error: nil)
    #expect(recovered)
}

@Test @MainActor func productionUpdaterCanStartWithConfiguredBundle() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReKey-updater-fixture-\(UUID().uuidString).bundle")
    defer { try? FileManager.default.removeItem(at: root) }
    let contents = root.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let info: [String: Any] = [
        "CFBundleIdentifier": "org.example.rekey.updaterfixture.\(UUID().uuidString)",
        "CFBundleName": "UpdaterFixture", "CFBundlePackageType": "BNDL",
        "CFBundleVersion": "100", "CFBundleShortVersionString": "1.0",
        "SUFeedURL": "https://example.invalid/appcast.xml",
        "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
        "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true,
        "SUEnableAutomaticChecks": false, "SUAllowsAutomaticUpdates": false
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    let bundle = try #require(Bundle(url: root))
    let controller = UpdateController(automaticChecks: false, bundle: bundle)
    #expect(controller.startupError == nil)
    #expect(controller.available)
}

@Test @MainActor func abortDuringInstallChoiceNeverStartsStagedUpdate() async throws {
    var continuation: CheckedContinuation<Void, Never>?
    var choice: SPUUserUpdateChoice?
    var aborts = 0
    let controller = UpdateController(automaticChecks: false, prepare: {
        await withCheckedContinuation { continuation = $0 }
    }, aborted: { _ in aborts += 1 })
    let sparkle = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    controller.handleUpdateChoice(.install) { choice = $0 }
    for _ in 0..<100 where continuation == nil { try await Task.sleep(for: .milliseconds(1)) }
    let resume = try #require(continuation)
    controller.updater(sparkle.updater, didAbortWithError: NSError(domain: "test", code: 1))
    resume.resume()
    for _ in 0..<100 where choice == nil { try await Task.sleep(for: .milliseconds(1)) }
    #expect(choice == .skip)
    #expect(aborts == 2)
}
