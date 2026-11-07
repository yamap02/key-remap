import SwiftUI
import AppKit

// Uses the same SwiftUI delegate adaptor as the app, but opens no windows and
// has no access to ReKey services or settings.
@main struct SwiftUITerminationProbe: App {
    @NSApplicationDelegateAdaptor(ReKeyApplicationDelegate.self) private var appDelegate

    init() {
        TerminationGate.updateServiceOperationInProgress = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSApplication.shared.terminate(nil)
            print("PASS SwiftUI refused termination during service transition")
            fflush(stdout)
            TerminationGate.updateServiceOperationInProgress = false
            print("PASS SwiftUI allowed termination after service transition")
            fflush(stdout)
            NSApplication.shared.terminate(nil)
            exit(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { exit(3) }
    }

    var body: some Scene { Settings { EmptyView() } }
}
