import Foundation
import Sparkle
import Testing
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
    }, preparationFailed: { _ in failed = true })
    let sparkle = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    #expect(controller.updater(sparkle.updater, shouldPostponeRelaunchForUpdate: .empty(), untilInvoking: { installed = true }))
    for _ in 0..<100 where !failed { try await Task.sleep(for: .milliseconds(1)) }
    #expect(failed)
    #expect(!installed)
}
