import Foundation

/// Shared names are derived from the build's product identifier, not the
/// Agent's own bundle identifier. The fallback supports developer test hosts.
public enum ReKeyServiceIdentity {
    public static func productID(in bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "ReKeyProductIdentifier") as? String) ?? "jp.example.rekey"
    }
    public static func coreName(in bundle: Bundle = .main) -> String { productID(in: bundle) + ".core" }
    public static func agentName(in bundle: Bundle = .main) -> String { productID(in: bundle) + ".agent" }
    public static func permissionNotification(in bundle: Bundle = .main) -> String { agentName(in: bundle) + ".request-permissions" }
}
