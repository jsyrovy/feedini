import SwiftUI
import WebKit

/// A source page in a `WKWebView`: the default persistent website data (logins and cookies work), JavaScript on, no
/// bridge to the app. Links that leave the page (and new windows) open in the default browser. Esc goes back to the
/// feed text; the page takes the keyboard focus only when clicked into.
struct WebPageView: NSViewRepresentable {
    let url: URL
    let onEscape: @MainActor () -> Void
    let onRefusedFocus: @MainActor () -> Void

    func makeNSView(context: Context) -> EscapableWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = EscapableWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.onEscape = onEscape
        webView.onRefusedFocus = onRefusedFocus
        webView.load(URLRequest(url: url))
        context.coordinator.loadedURL = url
        return webView
    }

    func updateNSView(_ webView: EscapableWebView, context: Context) {
        webView.onEscape = onEscape
        webView.onRefusedFocus = onRefusedFocus
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loadedURL: URL?

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated, navigationAction.targetFrame?.isMainFrame != false,
                let url = navigationAction.request.url
            else { return .allow }
            NSWorkspace.shared.open(url)
            return .cancel
        }

        func webView(
            _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}

/// A web view that hands Esc back to the app instead of the page, and takes the keyboard focus only when the user
/// clicks into it: a page that focuses a field of its own would otherwise take J/K away from the list (the preferred
/// view shows pages while walking the list). The window takes the focus from the list before it asks the web view,
/// so a refused focus goes back to the list (`onRefusedFocus`).
final class EscapableWebView: WKWebView {
    var onEscape: (@MainActor () -> Void)?
    var onRefusedFocus: (@MainActor () -> Void)?

    override func becomeFirstResponder() -> Bool {
        // The window makes a clicked view the first responder before it gets the click.
        if let event = NSApp.currentEvent, [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
            event.window === window, bounds.contains(convert(event.locationInWindow, from: nil))
        {
            return super.becomeFirstResponder()
        }
        Task { @MainActor [onRefusedFocus] in onRefusedFocus?() }
        return false
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}
