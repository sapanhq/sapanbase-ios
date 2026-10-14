# HelpBentoSDK (iOS)

HelpBento AI chat widget for native iOS apps.

This package renders **no native chat UI**. `HelpBento.shared.open(from:)`
presents a `WKWebView` that loads the same `widget.js` powering the
JavaScript SDK, and drives it through a small JS bridge. One UI source of
truth: widget fixes and new features ship server-side, with no SDK update
required.

## Install (Swift Package Manager)

In Xcode: **File → Add Package Dependencies…** and enter:

```
https://github.com/BentoSoftware/helpbento-ios
```

Or add it to your `Package.swift`:

```swift
.package(url: "https://github.com/BentoSoftware/helpbento-ios", from: "0.1.0")
```

## Quick start

Initialize once, early — e.g. in `AppDelegate` or your `SceneDelegate`:

```swift
import HelpBentoSDK

HelpBento.shared.delegate = self
HelpBento.shared.initialize(companyId: "YOUR_COMPANY_ID")
```

Identify the user after login, with an HMAC signature generated on **your**
server (see the HelpBento widget integration guide for the signing recipe):

```swift
HelpBento.shared.identify(
    userId: user.id,
    email: user.email,
    name: user.displayName,
    hmac: hmacFromYourServer
)
```

Open the chat from a Help button:

```swift
@IBAction func helpButtonTapped(_ sender: Any) {
    HelpBento.shared.open() // or open(from: self) to present from a specific VC
}
```

On logout:

```swift
HelpBento.shared.clearUser()
```

## API

| Method | Description |
|---|---|
| `initialize(companyId:agentId:scriptURL:)` | Load and prepare the widget. Call once, early — the webview pre-warms off-screen so the first `open()` is instant. Calling again tears down the previous session. |
| `identify(userId:email:name:hmac:)` | Identify the logged-in user. Safe to call right after `initialize()`; queued until the widget is ready. |
| `clearUser()` | Clear identity on logout. |
| `open(from:)` | Present the chat panel modally. `presenter` defaults to the top-most view controller of the key window. |
| `close()` | Dismiss the chat panel. |
| `destroy()` | Tear down the widget; `initialize()` may be called again. |
| `isOpen` | Whether the chat panel is currently open. |
| `delegate` | A `HelpBentoDelegate` for lifecycle and message events. |

All methods are safe to call from any thread.

## Delegate

```swift
extension AppDelegate: HelpBentoDelegate {
    func helpBentoDidOpen() { }
    func helpBentoDidClose() { }
    func helpBentoDidReceiveMessage(content: String) { }
    func helpBentoDidFailWithError(message: String) { }
}
```

Every method has an empty default implementation, so implement only what you
need.

## Domain allowlist

If your workspace restricts the widget to specific domains (Settings >
Support Agents), leave the allowlist **empty** when shipping this SDK. The
webview's requests won't match a domain-based allowlist, and mobile-app
allowlisting isn't supported yet — a non-empty allowlist will block the
widget from loading.
