import Foundation

/// Receives lifecycle and message events from the HelpBento chat widget.
///
/// All methods have empty default implementations, so a conforming type only
/// needs to implement the callbacks it cares about. Every callback is
/// delivered on the main thread.
public protocol HelpBentoDelegate: AnyObject {
    /// The chat panel was presented and became visible.
    func helpBentoDidOpen()

    /// The chat panel was dismissed, either via its own close control or a
    /// user swipe-to-dismiss gesture.
    func helpBentoDidClose()

    /// The assistant sent a reply. `content` is the reply text (markdown).
    func helpBentoDidReceiveMessage(content: String)

    /// The widget encountered an error (e.g. a failed network request).
    func helpBentoDidFailWithError(message: String)
}

/// Default no-op implementations so every delegate method is optional.
public extension HelpBentoDelegate {
    func helpBentoDidOpen() {}
    func helpBentoDidClose() {}
    func helpBentoDidReceiveMessage(content: String) {}
    func helpBentoDidFailWithError(message: String) {}
}
