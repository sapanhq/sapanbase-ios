import UIKit

/// Entry point for the HelpBento iOS SDK.
///
/// `HelpBento` is a thin `WKWebView` shell around the hosted HelpBento chat
/// widget: it renders no native chat UI of its own. Widget fixes and new
/// features ship server-side, with no SDK update required.
///
/// ```swift
/// HelpBento.shared.delegate = self
/// HelpBento.shared.initialize(companyId: "YOUR_COMPANY_ID")
/// // ...later, e.g. from a Help button:
/// HelpBento.shared.open()
/// ```
///
/// Every method is safe to call from any thread; work is hopped to the main
/// thread internally.
public final class HelpBento: NSObject {

    /// The shared SDK instance. HelpBento supports a single chat session per
    /// app process.
    public static let shared = HelpBento()

    /// Receives widget lifecycle and message events. Held weakly.
    public weak var delegate: HelpBentoDelegate?

    /// Whether the chat panel is currently open. Tracks native presentation
    /// state, updated from the widget's own open/close events and from an
    /// interactive swipe-to-dismiss.
    public private(set) var isOpen: Bool = false

    private static let defaultScriptURL = URL(string: "https://app.helpbento.com/widget.js")!

    private var chatViewController: ChatViewController?
    private var isReady = false
    private var pendingIdentity: PendingIdentity?
    private var pendingOpenRequested = false

    private enum PendingIdentity {
        case identify(userId: String, email: String?, name: String?, hmac: String?)
        case clear
    }

    private override init() {
        super.init()
    }

    /// Load the widget and prepare it for display.
    ///
    /// Call once, early (e.g. app or scene launch): the webview loads
    /// off-screen so the first `open()` is instant. Calling this again tears
    /// down any previous session first, so it's safe to call again after a
    /// user switch.
    ///
    /// - Parameters:
    ///   - companyId: Your HelpBento company ID (Settings > Widget Embed).
    ///   - agentId: Target a specific support agent. Defaults to the
    ///     company's default agent.
    ///   - scriptURL: Where to load `widget.js` from. Defaults to
    ///     `https://app.helpbento.com/widget.js`. Override only for local
    ///     development against the Firebase emulators — `widget.js` derives
    ///     its API base URL from this script's origin, so it must be a real
    ///     `http(s)` URL, never a file bundled into the app.
    public func initialize(companyId: String, agentId: String? = nil, scriptURL: URL? = nil) {
        runOnMain { [self] in
            teardown()

            let controller = ChatViewController(
                companyId: companyId,
                agentId: agentId,
                scriptURL: scriptURL ?? Self.defaultScriptURL
            )
            wire(controller)
            chatViewController = controller
            // Force the view (and thus the webview page load) to start now,
            // off-screen, so the widget is ready by the time open() is called.
            controller.loadViewIfNeeded()
        }
    }

    /// Identify the logged-in user.
    ///
    /// Safe to call immediately after `initialize()`: if the widget isn't
    /// ready yet, the call is queued and applied once it is.
    ///
    /// - Parameters:
    ///   - userId: Unique identifier for the user.
    ///   - email: The user's email address.
    ///   - name: The user's display name.
    ///   - hmac: The `v1.`-prefixed HMAC-SHA256 signature your server generates
    ///     over `"<userId>\n<email>"` (empty email after the newline when none
    ///     is supplied) — see the HelpBento widget integration guide. Passed
    ///     through as-is. Required for the user to show as verified.
    public func identify(userId: String, email: String? = nil, name: String? = nil, hmac: String? = nil) {
        runOnMain { [self] in
            guard chatViewController != nil else {
                assertionFailure("HelpBento: call initialize() before identify()")
                return
            }
            let pending = PendingIdentity.identify(userId: userId, email: email, name: name, hmac: hmac)
            if isReady {
                apply(pending)
            } else {
                pendingIdentity = pending
            }
        }
    }

    /// Clear the identified user (call on logout). Messages already sent keep
    /// the identity they were sent with; subsequent ones are anonymous.
    public func clearUser() {
        runOnMain { [self] in
            guard chatViewController != nil else { return }
            if isReady {
                apply(.clear)
            } else {
                pendingIdentity = .clear
            }
        }
    }

    /// Present the chat panel.
    ///
    /// - Parameter presenter: The view controller to present from. When
    ///   `nil`, the top-most view controller of the key window is used.
    public func open(from presenter: UIViewController? = nil) {
        runOnMain { [self] in
            guard let controller = chatViewController else {
                assertionFailure("HelpBento: call initialize() before open()")
                return
            }
            if controller.presentingViewController == nil {
                guard let host = presenter ?? Self.topViewController() else {
                    assertionFailure("HelpBento: no view controller available to present from")
                    return
                }
                host.present(controller, animated: true)
            }
            if isReady {
                controller.evaluateJS("window.HelpBento && window.HelpBento.open();")
            } else {
                pendingOpenRequested = true
            }
        }
    }

    /// Dismiss the chat panel.
    public func close() {
        runOnMain { [self] in
            pendingOpenRequested = false
            chatViewController?.evaluateJS("window.HelpBento && window.HelpBento.close();")
            finishClose()
        }
    }

    /// Tear everything down: dismisses the panel if presented, destroys the
    /// widget's JS state, and releases the webview. `initialize()` may be
    /// called again afterward.
    public func destroy() {
        runOnMain { [self] in
            teardown()
        }
    }

    // MARK: - Private

    private func wire(_ controller: ChatViewController) {
        controller.onReady = { [weak self] in
            guard let self else { return }
            self.isReady = true
            self.flushPending()
        }
        controller.onEvent = { [weak self] event, payload in
            self?.handle(event: event, payload: payload)
        }
        controller.onInteractiveDismiss = { [weak self] in
            self?.finishClose()
        }
        controller.onLoadFailure = { [weak self] message in
            self?.delegate?.helpBentoDidFailWithError(message: message)
        }
    }

    private func flushPending() {
        guard let controller = chatViewController else { return }
        if let pending = pendingIdentity {
            apply(pending)
            pendingIdentity = nil
        }
        if pendingOpenRequested {
            controller.evaluateJS("window.HelpBento && window.HelpBento.open();")
            pendingOpenRequested = false
        }
    }

    private func apply(_ identity: PendingIdentity) {
        switch identity {
        case let .identify(userId, email, name, hmac):
            var user: [String: Any] = ["userId": userId]
            if let email { user["email"] = email }
            if let name { user["name"] = name }
            if let hmac { user["hmac"] = hmac }
            chatViewController?.evaluateJS("window.HelpBento && window.HelpBento.identify(\(ChatViewController.jsonString(from: user)));")
        case .clear:
            chatViewController?.evaluateJS("window.HelpBento && window.HelpBento.clearUser();")
        }
    }

    private func handle(event: String, payload: [String: Any]?) {
        switch event {
        case "open":
            isOpen = true
            delegate?.helpBentoDidOpen()
        case "close":
            finishClose()
        case "message":
            delegate?.helpBentoDidReceiveMessage(content: (payload?["content"] as? String) ?? "")
        case "error":
            delegate?.helpBentoDidFailWithError(message: (payload?["message"] as? String) ?? "Unknown widget error")
        default:
            break
        }
    }

    /// Single idempotent teardown path for "the panel just closed," reachable
    /// from three signals: the public `close()` call, the widget's own close
    /// button (bridged `'close'` JS event), and an interactive swipe
    /// dismissal. Safe to call redundantly from more than one of those in the
    /// same close — the delegate fires at most once per open session, and
    /// dismissal is a no-op once the controller is no longer presented.
    private func finishClose() {
        let wasOpen = isOpen
        isOpen = false
        if let controller = chatViewController, controller.presentingViewController != nil {
            controller.dismiss(animated: true)
        }
        if wasOpen {
            delegate?.helpBentoDidClose()
        }
    }

    private func teardown() {
        if let controller = chatViewController {
            controller.evaluateJS("window.HelpBento && window.HelpBento.destroy();")
            if controller.presentingViewController != nil {
                controller.dismiss(animated: false)
            }
        }
        chatViewController = nil
        isReady = false
        isOpen = false
        pendingIdentity = nil
        pendingOpenRequested = false
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? keyWindowRootViewController()
        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }

    private static func keyWindowRootViewController() -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                return window.rootViewController
            }
        }
        return nil
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
