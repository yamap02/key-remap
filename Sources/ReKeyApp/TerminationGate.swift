import AppKit

@MainActor enum TerminationGate {
    static var updateServiceOperationInProgress = false
}

@MainActor final class ReKeyApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if TerminationGate.updateServiceOperationInProgress {
            return .terminateCancel
        }
        return .terminateNow
    }
}
