import Foundation

/// Receives lifecycle and message events from the SapanBase chat widget.
///
/// All methods have empty default implementations, so a conforming type only
/// needs to implement the callbacks it cares about. Every callback is
/// delivered on the main thread.
public protocol SapanBaseDelegate: AnyObject {
    /// The chat panel was presented and became visible.
    func sapanBaseDidOpen()

    /// The chat panel was dismissed, either via its own close control or a
    /// user swipe-to-dismiss gesture.
    func sapanBaseDidClose()

    /// The assistant sent a reply. `content` is the reply text (markdown).
    func sapanBaseDidReceiveMessage(content: String)

    /// The widget encountered an error (e.g. a failed network request).
    func sapanBaseDidFailWithError(message: String)
}

/// Default no-op implementations so every delegate method is optional.
public extension SapanBaseDelegate {
    func sapanBaseDidOpen() {}
    func sapanBaseDidClose() {}
    func sapanBaseDidReceiveMessage(content: String) {}
    func sapanBaseDidFailWithError(message: String) {}
}
