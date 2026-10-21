import Testing
import ReKeyIPC

@Test func ordinaryControlsDoNotRequireAnOptionalSubrole() {
    for role in ["AXTextArea", "AXTextField", "AXButton", "AXOutline"] {
        #expect(!FocusPrivacy.suppressesEvents(role: .value(role), subrole: .absent, secureInput: false))
    }
    #expect(!FocusPrivacy.suppressesEvents(role: .value("AXTextField"), subrole: .value("AXSearchField"), secureInput: false))
}

@Test func passwordAndSecureInputRemainHidden() {
    #expect(FocusPrivacy.suppressesEvents(role: .value("AXTextField"), subrole: .value("AXSecureTextField"), secureInput: false))
    #expect(FocusPrivacy.suppressesEvents(role: .value("AXSecureTextField"), subrole: .absent, secureInput: false))
    #expect(FocusPrivacy.suppressesEvents(role: .value("AXTextArea"), subrole: .absent, secureInput: true))
}

@Test func unreadableOrUnknownFocusRemainsHidden() {
    for role in [FocusAttribute.unavailable, .absent, .value(""), .value("AXUnknown")] {
        #expect(FocusPrivacy.suppressesEvents(role: role, subrole: .absent, secureInput: false))
    }
    #expect(FocusPrivacy.suppressesEvents(role: .value("AXTextArea"), subrole: .unavailable, secureInput: false))
    #expect(FocusPrivacy.suppressesEvents(role: .value("AXTextArea"), subrole: .value(""), secureInput: false))
}
