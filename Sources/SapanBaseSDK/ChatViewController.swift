import UIKit
import WebKit

/// Presents the SapanBase web chat widget in a `WKWebView` and bridges its
/// JavaScript events back to native closures. Internal only — hosts interact
/// with the widget exclusively through `SapanBase`, never this type.
///
/// The controller renders no native chat UI of its own: it loads a small
/// generated HTML page that pulls in the production `widget.js` and drives it
/// entirely from JavaScript, so widget fixes and UI changes ship server-side.
final class ChatViewController: UIViewController {

    /// The JS bridge's message handler name, referenced by both the native
    /// `WKUserContentController` registration and the generated page script.
    static let bridgeHandlerName = "sapanbase"

    /// Fired once the widget reports `'ready'` (its DOM exists; `open()` and
    /// `identify()` are safe to call in JS from this point on).
    var onReady: (() -> Void)?

    /// Fired for every other bridged widget event (`open`, `close`,
    /// `message`, `error`) with its JSON payload decoded to a dictionary.
    var onEvent: ((_ event: String, _ payload: [String: Any]?) -> Void)?

    /// Fired when the presented sheet is dismissed by a user swipe gesture.
    /// Not fired for a programmatic `dismiss(animated:)` call.
    var onInteractiveDismiss: (() -> Void)?

    /// Fired when the initial page fails to load.
    var onLoadFailure: ((String) -> Void)?

    private let companyId: String
    private let agentId: String?
    private let scriptURL: URL

    private var webView: WKWebView!

    /// Designated initializer.
    /// - Parameters:
    ///   - companyId: The SapanBase company ID passed to `widget.js`'s `init`.
    ///   - agentId: Optional agent ID passed to `widget.js`'s `init`.
    ///   - scriptURL: Where to load `widget.js` from.
    init(companyId: String, agentId: String?, scriptURL: URL) {
        self.companyId = companyId
        self.agentId = agentId
        self.scriptURL = scriptURL
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.bridgeHandlerName)
    }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(
            ScriptMessageHandlerProxy(target: self),
            name: Self.bridgeHandlerName
        )
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.backgroundColor = .systemBackground
        webView.scrollView.bounces = false
        self.webView = webView
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Attach the swipe-to-dismiss delegate once the presentation
        // controller exists (created when the VC enters a presentation
        // context), so an interactive dismissal is observable.
        presentationController?.delegate = self
        webView.loadHTMLString(
            Self.pageHTML(companyId: companyId, agentId: agentId, scriptURL: scriptURL),
            baseURL: Self.origin(of: scriptURL)
        )
    }

    /// The scheme+host+port of `url`, with an empty path — the "origin" the
    /// generated page should be loaded against, so the webview's document
    /// origin (and anything `widget.js` derives from it) matches the origin
    /// the script itself was served from, not a sub-path of it.
    private static func origin(of url: URL) -> URL {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        return components.url ?? url
    }

    /// Evaluate JavaScript in the page. Best-effort: the widget bridge has no
    /// return value contract, so failures are not surfaced to callers.
    func evaluateJS(_ script: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    /// Route an incoming bridge message to the `onReady`/`onEvent` closures.
    fileprivate func handleBridgeMessage(_ body: Any) {
        guard let dict = body as? [String: Any], let event = dict["event"] as? String else { return }
        if event == "ready" {
            onReady?()
        } else {
            onEvent?(event, dict["payload"] as? [String: Any])
        }
    }

    /// Open `url` in the system browser. Only `http`/`https` are honored.
    private func openExternally(_ url: URL) {
        guard url.scheme == "http" || url.scheme == "https" else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // MARK: - HTML page generation

    /// Build the HTML page loaded into the webview: a viewport meta tag, the
    /// production `widget.js` script tag, and an inline script that wires the
    /// widget's five events to the native bridge and then calls `init()`.
    private static func pageHTML(companyId: String, agentId: String?, scriptURL: URL) -> String {
        let configJSON = widgetInitJSON(companyId: companyId, agentId: agentId)
        let scriptSrc = htmlAttributeEscaped(scriptURL.absoluteString)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
        <style>html,body{margin:0;padding:0;height:100%;background:transparent;}</style>
        </head>
        <body>
        <script src="\(scriptSrc)"></script>
        <script>
        (function () {
          function post(event, payload) {
            try {
              window.webkit.messageHandlers.\(bridgeHandlerName).postMessage({ event: event, payload: payload || null });
            } catch (e) { /* bridge unavailable; nothing to do */ }
          }
          function wireAndInit() {
            if (!window.SapanBase) {
              setTimeout(wireAndInit, 30);
              return;
            }
            window.SapanBase.on('ready', function () { post('ready'); });
            window.SapanBase.on('open', function () { post('open'); });
            window.SapanBase.on('close', function () { post('close'); });
            window.SapanBase.on('message', function (payload) { post('message', payload); });
            window.SapanBase.on('error', function (payload) { post('error', payload); });
            window.SapanBase.init(\(configJSON));
          }
          wireAndInit();
        })();
        </script>
        </body>
        </html>
        """
    }

    /// JSON-encode the `widget.js` `init()` config. `companyId`/`agentId` are
    /// developer-supplied strings, so they're encoded with `JSONSerialization`
    /// rather than interpolated raw into the script.
    private static func widgetInitJSON(companyId: String, agentId: String?) -> String {
        var config: [String: Any] = [
            "companyId": companyId,
            "platform": "ios",
            "showLauncher": false,
            "animations": true,
        ]
        if let agentId {
            config["agentId"] = agentId
        }
        return jsonString(from: config)
    }

    /// Serialize `object` to a JSON string safe to inline into a `<script>`
    /// block. Escapes U+2028/U+2029, which are legal in JSON strings but are
    /// JavaScript line terminators, so an unescaped one would be a syntax
    /// error rather than data. Shared with `SapanBase` for bridge calls
    /// (`identify`) made after the page has already loaded.
    static func jsonString(from object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private static func htmlAttributeEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}

// MARK: - WKScriptMessageHandler proxy

/// `WKUserContentController.add(_:name:)` retains its handler strongly. Since
/// the controller lives on `webView.configuration`, which `ChatViewController`
/// owns via its `view`, registering `self` directly would form a retain
/// cycle. This proxy breaks it by holding the real target weakly.
private final class ScriptMessageHandlerProxy: NSObject, WKScriptMessageHandler {
    private weak var target: ChatViewController?

    init(target: ChatViewController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == ChatViewController.bridgeHandlerName else { return }
        target?.handleBridgeMessage(message.body)
    }
}

// MARK: - WKNavigationDelegate

extension ChatViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Only the initial `loadHTMLString` content may load in-frame; any
        // link tap (including one that would otherwise navigate the frame)
        // opens in the system browser instead.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            openExternally(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadFailure?(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadFailure?(error.localizedDescription)
    }
}

// MARK: - WKUIDelegate

extension ChatViewController: WKUIDelegate {
    /// A `target="_blank"` link or `window.open()` call requests a new
    /// webview; open the URL externally instead and create none.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            openExternally(url)
        }
        return nil
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension ChatViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onInteractiveDismiss?()
    }
}
