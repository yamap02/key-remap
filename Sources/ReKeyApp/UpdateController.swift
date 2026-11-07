import Foundation
import Sparkle

// A development build has no feed or public key and never starts Sparkle.
@MainActor final class UpdateController {
    private let controller: SPUStandardUpdaterController?
    var available: Bool { controller != nil }

    init(automaticChecks: Bool, bundle: Bundle = .main) {
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let decoded = Data(base64Encoded: key), decoded.count == 32 else {
            controller = nil
            return
        }
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        updater.updater.automaticallyChecksForUpdates = automaticChecks
        updater.updater.automaticallyDownloadsUpdates = false
        updater.startUpdater()
        controller = updater
    }

    func setAutomaticChecks(_ enabled: Bool) { controller?.updater.automaticallyChecksForUpdates = enabled }
    func checkNow() { controller?.checkForUpdates(nil) }
}
