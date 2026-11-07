import Foundation
import Sparkle

// Intercept the user's first install choice, before Sparkle can prepare an
// install-on-quit update. The standard presentation and all other UI are kept.
@MainActor final class PreparingUserDriver: SPUStandardUserDriver {
    var handleChoice: ((SPUUserUpdateChoice, @escaping (SPUUserUpdateChoice) -> Void) -> Void)?
    var handleReadyChoice: ((SPUUserUpdateChoice) -> Void)?

    override func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState,
                                  reply: @escaping (SPUUserUpdateChoice) -> Void) {
        super.showUpdateFound(with: item, state: state) { [weak self] choice in
            guard let self, let handleChoice = self.handleChoice else { reply(.dismiss); return }
            handleChoice(choice, reply)
        }
    }

    override func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        let choice = await super.showReadyToInstallAndRelaunch()
        handleReadyChoice?(choice)
        return choice
    }
}

// A development build has no feed or public key and never starts Sparkle.
@MainActor final class UpdateController: NSObject, SPUUpdaterDelegate {
    private var updater: SPUUpdater?
    private var userDriver: PreparingUserDriver?
    private let prepare: @MainActor () async throws -> Void
    private let preparationFailed: @MainActor (Error) -> Void
    private let pendingInstallFailed: @MainActor (Error) -> Void
    private let aborted: @MainActor (Error) -> Void
    private var preparationGeneration = 0
    private var cancellationRequested = false
    private var cancellationFailure: Error?
    private(set) var startupError: String?
    var available: Bool { updater != nil }

    init(automaticChecks: Bool, bundle: Bundle = .main,
         prepare: @escaping @MainActor () async throws -> Void = {},
         preparationFailed: @escaping @MainActor (Error) -> Void = { _ in },
         pendingInstallFailed: @escaping @MainActor (Error) -> Void = { _ in },
         aborted: @escaping @MainActor (Error) -> Void = { _ in }) {
        self.prepare = prepare
        self.preparationFailed = preparationFailed
        self.pendingInstallFailed = pendingInstallFailed
        self.aborted = aborted
        super.init()
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let decoded = Data(base64Encoded: key), decoded.count == 32 else { return }
        let driver = PreparingUserDriver(hostBundle: bundle, delegate: nil)
        driver.handleChoice = { [weak self] choice, reply in
            guard let self else { reply(.dismiss); return }
            self.handleUpdateChoice(choice, reply: reply)
        }
        driver.handleReadyChoice = { [weak self] choice in
            if choice == .skip { self?.cancellationRequested = true }
        }
        let instance = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: self)
        instance.automaticallyChecksForUpdates = automaticChecks
        instance.automaticallyDownloadsUpdates = false
        do { try instance.start() }
        catch { startupError = error.localizedDescription; return }
        userDriver = driver
        updater = instance
    }

    func handleUpdateChoice(_ choice: SPUUserUpdateChoice, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard choice == .install else {
            if choice == .skip { cancellationRequested = true }
            reply(choice); return
        }
        cancellationRequested = false
        cancellationFailure = nil
        preparationGeneration += 1
        let generation = preparationGeneration
        Task { @MainActor in
            do {
                try await prepare()
                if generation == preparationGeneration { reply(.install) }
                else { reply(.skip); aborted(NSError(domain: "ReKey.Update", code: 4)) }
            } catch {
                if generation == preparationGeneration {
                    cancellationRequested = true
                    cancellationFailure = error
                    // Skip cancels even an already staged update. Dismiss does not.
                    reply(.skip)
                } else {
                    reply(.skip)
                    aborted(error)
                }
            }
        }
    }

    // Defense in depth for the explicit relaunch path. Preparation is
    // idempotent after the first install choice has stopped the services.
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
                if generation == preparationGeneration { pendingInstallFailed(error) }
                else { aborted(error) }
            }
        }
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        preparationGeneration += 1
        if !cancellationRequested { aborted(error) }
    }

    @objc(updater:didFinishUpdateCycleForUpdateCheck:error:)
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if cancellationRequested {
            cancellationRequested = false
            if let failure = cancellationFailure {
                cancellationFailure = nil
                preparationFailed(failure)
            } else {
                aborted(error ?? NSError(domain: "ReKey.Update", code: 5))
            }
        }
    }

    func setAutomaticChecks(_ enabled: Bool) { updater?.automaticallyChecksForUpdates = enabled }
    func checkNow() { updater?.checkForUpdates() }
}
