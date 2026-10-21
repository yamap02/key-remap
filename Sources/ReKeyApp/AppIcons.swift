import AppKit

@MainActor enum AppIcons {
    static let active = template("MenuActive", fallback: "arrow.left.arrow.right")
    static let paused = template("MenuPaused", fallback: "pause.circle")
    static let attention = template("MenuAttention", fallback: "keyboard.badge.ellipsis")

    private static func template(_ name: String, fallback: String) -> NSImage {
        let image = Bundle.main.url(forResource: name, withExtension: "pdf")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: nil)!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
