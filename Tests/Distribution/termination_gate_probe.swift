import AppKit

@main struct TerminationProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ReKeyApplicationDelegate()
        app.delegate = delegate
        TerminationGate.updateServiceOperationInProgress = true
        DispatchQueue.main.async {
            // terminate returns only when AppKit accepts the delegate's cancel.
            app.terminate(nil)
            print("PASS termination refused during service transition")
            fflush(stdout)
            TerminationGate.updateServiceOperationInProgress = false
            print("PASS termination allowed after service transition")
            fflush(stdout)
            app.terminate(nil)
            // An accepted terminate should end the process, not return here.
            exit(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { exit(3) }
        withExtendedLifetime(delegate) { app.run() }
        exit(4)
    }
}
