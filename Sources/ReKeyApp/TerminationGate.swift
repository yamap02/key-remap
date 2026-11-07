import AppKit

@MainActor enum TerminationGate {
    static var updateServiceOperationInProgress = false
    static var requiresPendingVerification = false
    static var verifyPendingUpdate: (@MainActor () -> Bool)?
}

@MainActor final class ReKeyApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if TerminationGate.updateServiceOperationInProgress {
            return .terminateCancel
        }
        if TerminationGate.requiresPendingVerification {
            guard let verify = TerminationGate.verifyPendingUpdate, verify() else { return .terminateCancel }
        }
        return .terminateNow
    }
}
