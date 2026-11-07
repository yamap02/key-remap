import AppKit
import Sparkle

@MainActor final class Probe: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { print("FOUND \(item.versionString)"); fflush(stdout); exit(0) }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { print("NONE"); fflush(stdout); exit(0) }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { print("ERROR \((error as NSError).code)"); fflush(stdout); exit(0) }
}
@main struct Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = Probe()
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
        controller.startUpdater()
        controller.updater.checkForUpdateInformation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { print("TIMEOUT"); exit(2) }
        withExtendedLifetime((delegate, controller)) { app.run() }
    }
}
