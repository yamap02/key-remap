import AppKit

@main struct PendingTerminationProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ReKeyApplicationDelegate()
        app.delegate = delegate
        TerminationGate.requiresPendingVerification = true
        var attempts = 0
        TerminationGate.verifyPendingUpdate = {
            attempts += 1
            print("VERIFY \(attempts)")
            fflush(stdout)
            return attempts > 1
        }
        DispatchQueue.main.async { print("REQUEST 1"); fflush(stdout); app.terminate(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard attempts == 1 else { exit(2) }
            print("PASS unsafe pending update blocked termination")
            fflush(stdout)
            app.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { exit(3) }
        withExtendedLifetime(delegate) { app.run() }
        exit(4)
    }
}
