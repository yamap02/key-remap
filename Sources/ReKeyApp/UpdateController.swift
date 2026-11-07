import Foundation
import Sparkle

// A development build has no feed or public key and never starts Sparkle.
@MainActor final class UpdateController: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    private let prepare: @MainActor () async throws -> Void
    private let preparationFailed: @MainActor (Error) -> Void
    private let aborted: @MainActor (Error) -> Void
    private var preparationGeneration = 0
    var available: Bool { controller != nil }

    init(automaticChecks: Bool, bundle: Bundle = .main,
         prepare: @escaping @MainActor () async throws -> Void = {},
         preparationFailed: @escaping @MainActor (Error) -> Void = { _ in },
         aborted: @escaping @MainActor (Error) -> Void = { _ in }) {
        self.prepare = prepare
        self.preparationFailed = preparationFailed
        self.aborted = aborted
        super.init()
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let decoded = Data(base64Encoded: key), decoded.count == 32 else {
            return
        }
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        updater.updater.automaticallyChecksForUpdates = automaticChecks
        updater.updater.automaticallyDownloadsUpdates = false
        updater.startUpdater()
        controller = updater
    }

    @objc(updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvoking installHandler: @escaping () -> Void) -> Bool {
        preparationGeneration += 1
        let generation = preparationGeneration
        Task { @MainActor in
            do {
                try await prepare()
                if generation == preparationGeneration { installHandler() }
                else { aborted(NSError(domain: "ReKey.Update", code: 4)) }
            } catch {
                if generation == preparationGeneration { preparationFailed(error) }
                else { aborted(error) }
            }
        }
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        preparationGeneration += 1
        aborted(error)
    }

    func setAutomaticChecks(_ enabled: Bool) { controller?.updater.automaticallyChecksForUpdates = enabled }
    func checkNow() { controller?.checkForUpdates(nil) }
}
