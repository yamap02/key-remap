import Foundation

/// AXSubrole is optional; its absence is different from an AX messaging failure.
public enum FocusAttribute: Equatable, Sendable {
    case value(String)
    case absent
    case unavailable
}

public enum FocusPrivacy {
    public static func suppressesEvents(role: FocusAttribute, subrole: FocusAttribute, secureInput: Bool) -> Bool {
        if secureInput { return true }
        guard case .value(let roleName) = role, !roleName.isEmpty, roleName != "AXUnknown" else { return true }
        if roleName == "AXSecureTextField" { return true }
        switch subrole {
        case .value(let name): return name.isEmpty || name == "AXSecureTextField"
        case .absent: return false
        case .unavailable: return true
        }
    }
}
