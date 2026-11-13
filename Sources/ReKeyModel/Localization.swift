import Foundation
import Synchronization

private let cachedBundle = Mutex<Bundle?>(nil)
// The language picker writes UserDefaults; any defaults change just forces one re-resolution.
nonisolated(unsafe) private let languageObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
    cachedBundle.withLock { $0 = nil }
}

/// Looks up `key` in the lproj chosen by the app's "language" setting. The Japanese key is the
/// fallback, so processes without the tables (Agent, tests) keep the original text.
public func L(_ key: String) -> String {
    _ = languageObserver
    let bundle = cachedBundle.withLock { cached in
        if let cached { return cached }
        let language = UserDefaults.standard.string(forKey: "language") ?? "ja"
        let resolved = language == "system" ? Bundle.main : Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main
        cached = resolved
        return resolved
    }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}
