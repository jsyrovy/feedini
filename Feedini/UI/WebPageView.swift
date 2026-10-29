import SwiftUI
import WebKit

/// A source page in a `WKWebView`: the default persistent website data (logins and cookies work), JavaScript on, no
/// bridge to the app. Links that leave the page (and new windows) open in the default browser. Esc goes back to the
/// feed text.
struct WebPageView: NSViewRepresentable {
    let url: URL
    let onEscape: @MainActor () -> Void

    func makeNSView(context: Context) -> EscapableWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = EscapableWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.onEscape = onEscape
        webView.load(URLRequest(url: url))
        context.coordinator.loadedURL = url
        return webView
    }

    func updateNSView(_ webView: EscapableWebView, context: Context) {
        webView.onEscape = onEscape
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

/// A web view that hands Esc back to the app instead of the page.
final class EscapableWebView: WKWebView {
    var onEscape: (@MainActor () -> Void)?

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
