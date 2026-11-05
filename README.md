# SapanBaseSDK (iOS)

SapanBase AI chat widget for native iOS apps.

This package renders **no native chat UI**. `SapanBase.shared.open(from:)`
presents a `WKWebView` that loads the same `widget.js` powering the
JavaScript SDK, and drives it through a small JS bridge. One UI source of
truth: widget fixes and new features ship server-side, with no SDK update
required.

## Install (Swift Package Manager)

In Xcode: **File → Add Package Dependencies…** and enter:

```
https://github.com/sapanhq/sapanbase-ios
```

Or add it to your `Package.swift`:

```swift
.package(url: "https://github.com/sapanhq/sapanbase-ios", from: "0.2.0")
```

## Quick start

Initialize once, early — e.g. in `AppDelegate` or your `SceneDelegate`:

```swift
import SapanBaseSDK

SapanBase.shared.delegate = self
SapanBase.shared.initialize(companyId: "YOUR_COMPANY_ID")
```

Identify the user after login, with an HMAC signature generated on **your**
server (see the SapanBase widget integration guide for the signing recipe):

```swift
SapanBase.shared.identify(
    userId: user.id,
    email: user.email,
    name: user.displayName,
    hmac: hmacFromYourServer
)
```

Open the chat from a Help button:

```swift
@IBAction func helpButtonTapped(_ sender: Any) {
    SapanBase.shared.open() // or open(from: self) to present from a specific VC
}
```

On logout:

```swift
SapanBase.shared.clearUser()
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
| `delegate` | A `SapanBaseDelegate` for lifecycle and message events. |

All methods are safe to call from any thread.

## Delegate

```swift
extension AppDelegate: SapanBaseDelegate {
    func sapanBaseDidOpen() { }
    func sapanBaseDidClose() { }
    func sapanBaseDidReceiveMessage(content: String) { }
    func sapanBaseDidFailWithError(message: String) { }
}
```

Every method has an empty default implementation, so implement only what you
need.

## Your own support form

To send a native in-app support form (e.g. title, reason dropdown, details)
to the SapanBase inbox, post it from **your backend** to
`POST /v1/support-requests` with an API key, passing the signed-in user's
`userId` and your form answers as `customFields`. The request shows in the
inbox tied to the verified user. There's no SDK method for this: the API key
must stay on your server, never in the app.

## Domain allowlist

If your workspace restricts the widget to specific domains (Settings >
Support Agents), leave the allowlist **empty** when shipping this SDK. The
webview's requests won't match a domain-based allowlist, and mobile-app
allowlisting isn't supported yet — a non-empty allowlist will block the
widget from loading.
