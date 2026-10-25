import Testing
import ReKeyIPC

@Test func focusInspectionRequiresALiveViewerAndExpiresOnLostHeartbeat() {
    let now = ContinuousClock.now
    var lease = ViewerLease()
    #expect(!lease.allowsFocusInspection(at: now))
    lease.update(requested: true, at: now)
    #expect(lease.allowsFocusInspection(at: now + .milliseconds(499)))
    #expect(!lease.allowsFocusInspection(at: now + .milliseconds(500)))
    #expect(!lease.allowsFocusInspection(at: now + .seconds(10)))
    lease.update(requested: true, at: now)
    lease.update(requested: false, at: now + .milliseconds(10))
    #expect(!lease.allowsFocusInspection(at: now + .milliseconds(11)))
}
