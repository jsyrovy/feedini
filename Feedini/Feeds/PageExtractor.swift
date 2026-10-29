import Foundation
import WebKit

enum PageError: Error, Sendable, Equatable {
    /// Why, as `FetchError` words it.
    case loadFailed(String)
    case http(status: Int)
    case timedOut
    /// The page has (almost) no text.
    case noText

    /// For the user, in the detail.
    var message: String {
        switch self {
        case .loadFailed(let reason): "The page couldn't be loaded: \(reason)"
        case .http(let status): FetchError.http(status: status).message
        case .timedOut: "The page didn't load in time."
        case .noText: "The page has no readable text."
        }
    }
}

/// Loads source pages and extracts their text (`PageText.clean`); a protocol so the page queue can be tested without
/// WebKit.
@MainActor
protocol PageExtracting: AnyObject {
    func extract(_ url: URL) async throws(PageError) -> String
}

/// Cleans the text the extraction script returns (pure).
enum PageText {
    /// A safeguard against an extraction gone wrong (the whole page with comments, an endless list), not a limit of
    /// the model: a long article fits in whole.
    static let maxLength = 100_000
    /// Shorter texts count as no text (an empty page, a page that only says "Loading…").
    static let minLength = 100

    /// Whitespace collapsed within lines, empty lines and paragraphs dropped, cut to `maxLength` (ending in "…").
    /// `nil` for less than `minLength` characters.
    static func clean(_ raw: String) -> String? {
        let paragraphs = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph.split(separator: "\n")
                    .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }
            .filter { !$0.isEmpty }
        var text = paragraphs.joined(separator: "\n\n")
        guard text.count >= minLength else { return nil }
        if text.count > maxLength {
            text = text.prefix(maxLength - 1) + "…"
        }
        return text
    }

    /// Whether `clean` cut the text.
    static func isTruncated(_ text: String) -> Bool {
        text.hasSuffix("…") && text.count >= maxLength
    }
}

/// Loads a page in a hidden `WKWebView` and extracts the article's text with a script that doesn't change the page.
///
/// The web view uses the default website data store, shared with the source page in the window (`WebPageView`): a
/// cookie consent or a login given there counts here too. JavaScript is on (some sites render their articles in the
/// browser); images, media and fonts aren't loaded at all.
@MainActor
final class PageExtractor: PageExtracting {
    private static let blockedResources = """
        [{"trigger":{"url-filter":".*","resource-type":["image","media","font"]},"action":{"type":"block"}}]
        """

    private let dataStore: WKWebsiteDataStore
    private let settleDelay: Duration
    private let timeout: Duration
    /// Compiled on first use.
    private var resourceBlocker: WKContentRuleList?

    /// - Parameters:
    ///   - dataStore: the default one when `nil`.
    ///   - settleDelay: how long to wait after the page finished loading (late scripts, lazy content).
    ///   - timeout: for the whole extraction.
    init(dataStore: WKWebsiteDataStore? = nil, settleDelay: Duration = .seconds(1), timeout: Duration = .seconds(20)) {
        self.dataStore = dataStore ?? .default()
        self.settleDelay = settleDelay
        self.timeout = timeout
    }

    func extract(_ url: URL) async throws(PageError) -> String {
        try await load { $0.load(URLRequest(url: url)) }
    }

    /// Extracts the text of an HTML document (tests).
    func extract(html: String, baseURL: URL) async throws(PageError) -> String {
        try await load { $0.loadHTMLString(html, baseURL: baseURL) }
    }

    private func load(_ start: (WKWebView) -> Void) async throws(PageError) -> String {
        if resourceBlocker == nil {
            // Without it the page only loads more than it needs.
            resourceBlocker = try? await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "PageExtractor.blockedResources", encodedContentRuleList: Self.blockedResources)
        }
        let page = PageLoad(dataStore: dataStore, resourceBlocker: resourceBlocker, settleDelay: settleDelay)
        return try await page.run(timeout: timeout, start: start)
    }
}

/// One page in its own web view, from loading to the extracted text.
@MainActor
private final class PageLoad: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let settleDelay: Duration
    private var continuation: CheckedContinuation<Result<String, PageError>, Never>?
    private var settling: Task<Void, Never>?

    init(dataStore: WKWebsiteDataStore, resourceBlocker: WKContentRuleList?, settleDelay: Duration) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        if let resourceBlocker {
            configuration.userContentController.add(resourceBlocker)
        }
        // A desktop-sized layout, so the page shows its article column as in a browser.
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        self.settleDelay = settleDelay
        super.init()
        webView.navigationDelegate = self
    }

    func run(timeout: Duration, start: (WKWebView) -> Void) async throws(PageError) -> String {
        let deadline = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled {
                self?.finish(.failure(.timedOut))
            }
        }
        defer {
            deadline.cancel()
            settling?.cancel()
            webView.stopLoading()
            webView.navigationDelegate = nil
        }
        let result = await withCheckedContinuation { continuation in
            self.continuation = continuation
            start(webView)
        }
        return try result.get()
    }

    private func finish(_ result: Result<String, PageError>) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse,
            response.statusCode >= 400
        {
            finish(.failure(.http(status: response.statusCode)))
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // A redirect by script or meta refresh: wait for the next page.
        settling?.cancel()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        settling?.cancel()
        settling = Task { [weak self, settleDelay] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            await self?.extractText()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        fail(error)
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        fail(error)
    }

    private func fail(_ error: any Error) {
        // A navigation replaced by another one (a redirect) is cancelled; the new one goes on.
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        finish(.failure(.loadFailed(FetchError(error).message)))
    }

    private func extractText() async {
        let raw = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(PageScript.extract) { result, _ in
                continuation.resume(returning: result as? String)
            }
        }
        guard let raw else {
            finish(.failure(.loadFailed("The page's text couldn't be read.")))
            return
        }
        guard let text = PageText.clean(raw) else {
            finish(.failure(.noText))
            return
        }
        finish(.success(text))
    }
}

/// The extraction script: it only reads the page.
///
/// 1. Overlays are left out: cookie consent dialogs (CMPs) otherwise win, having the most continuous text. Out go
///    elements with `position: fixed`, dialogs, hidden elements and elements whose id or class names a consent tool.
///    Navigation, asides, headers, footers, forms, figures, comments and share buttons go too.
/// 2. The container of the article: the biggest `[itemprop=articleBody]`, else `article`, else `main` (with at least
///    500 characters of text), else the element whose paragraphs have the most text, else the body.
/// 3. The text of its blocks: paragraphs separated by a blank line, `<br>` as a line break (two as a paragraph), list
///    items with "• " on lines of their own, `pre` as it is. Blocks that are mostly links (menus, lists of other articles) are left out.
/// 4. JSON-LD `articleBody` only when that gives less than 500 characters: it is plain text without paragraphs.
enum PageScript {
    /// Returns the text, at most twice `PageText.maxLength` (cleaning only makes it shorter).
    static let extract = #"""
        (() => {
          const excluded = 'nav,aside,footer,header,form,figure,figcaption,dialog,button,select,textarea,' +
            '[role=navigation],[role=complementary],[role=banner],[role=contentinfo],[role=dialog],' +
            '[role=alertdialog],[aria-modal=true],[aria-hidden=true],.comments,#comments,.related,.share,.social,' +
            '.newsletter,.advert,.ad,.ads';
          const skipped = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'SVG', 'IFRAME', 'IMG', 'VIDEO',
            'AUDIO', 'CANVAS', 'INPUT', 'OBJECT', 'EMBED']);
          const consent = /consent|cookie|didomi|gdpr|privacy|souhlas|cmpbox|qc-cmp/i;
          const overlays = new Map();
          const isOwnOverlay = e => {
            if (!overlays.has(e)) {
              const style = getComputedStyle(e);
              const className = typeof e.className === 'string' ? e.className : '';
              overlays.set(e, style.position === 'fixed' || style.display === 'none' ||
                style.visibility === 'hidden' || consent.test(e.id || '') || consent.test(className));
            }
            return overlays.get(e);
          };
          const isOverlay = el => {
            for (let e = el; e && e !== document.body && e !== document.documentElement; e = e.parentElement) {
              if (isOwnOverlay(e)) return true;
            }
            return false;
          };
          const isExcluded = el => !!el.closest(excluded) || isOverlay(el);
          const textOf = el => ((el && el.innerText) || '').trim();

          // The container.
          let container = null;
          for (const selector of ['[itemprop=articleBody]', 'article', 'main,[role=main]']) {
            let longest = 0;
            for (const candidate of document.querySelectorAll(selector)) {
              if (isOverlay(candidate)) continue;
              const length = textOf(candidate).length;
              if (length > longest) { container = candidate; longest = length; }
            }
            if (longest >= 500) break;
            container = null;
          }
          if (!container) {
            const scores = new Map();
            const add = (el, value) => { if (el) scores.set(el, (scores.get(el) || 0) + value); };
            for (const p of document.querySelectorAll('p')) {
              if (isExcluded(p)) continue;
              const length = textOf(p).length;
              if (length < 40) continue;
              add(p.parentElement, length);
              add(p.parentElement && p.parentElement.parentElement, length / 2);
            }
            let best = 0;
            for (const [el, score] of scores) if (score > best) { container = el; best = score; }
            if (best < 500) container = null;
          }
          container = container || document.body;

          // The blocks.
          const blocks = [];
          let line = '', linkLength = 0;
          const flush = () => {
            const text = line.split('\n').map(l => l.replace(/\s+/g, ' ').trim()).filter(l => l).join('\n');
            const length = text.replace(/\s/g, '').length;
            if (text && linkLength / Math.max(length, 1) < 0.6) blocks.push(text);
            line = ''; linkLength = 0;
          };
          const isBlock = el => {
            const display = getComputedStyle(el).display;
            return !display.startsWith('inline') && display !== 'contents';
          };
          const walk = (node, inLink) => {
            for (const child of node.childNodes) {
              if (child.nodeType === Node.TEXT_NODE) {
                line += child.data;
                if (inLink) linkLength += child.data.replace(/\s/g, '').length;
                continue;
              }
              if (child.nodeType !== Node.ELEMENT_NODE || skipped.has(child.tagName.toUpperCase())) continue;
              // Ancestors up to the container were checked on the way down.
              if (child.matches(excluded) || isOwnOverlay(child)) continue;
              const tag = child.tagName;
              if (tag === 'BR') {
                if (/\n\s*$/.test(line)) flush(); else line += '\n';
              } else if (tag === 'PRE') {
                flush();
                const text = child.textContent.replace(/^\n+|\s+$/g, '');
                if (text) blocks.push(text);
              } else if (isBlock(child)) {
                flush();
                const first = blocks.length;
                walk(child, inLink || tag === 'A');
                flush();
                if (tag === 'LI' && blocks.length > first) blocks[first] = '• ' + blocks[first];
              } else {
                walk(child, inLink || tag === 'A');
              }
            }
          };
          walk(container, false);
          flush();
          // List items stay together on lines of their own.
          let text = blocks.map((block, i) =>
            (i > 0 && block.startsWith('• ') && blocks[i - 1].startsWith('• ') ? '\n' : '\n\n') + block
          ).join('').trim();

          if (text.length < 500) {
            let articleBody = '';
            const visit = o => {
              if (!o || typeof o !== 'object') return;
              if (Array.isArray(o)) { o.forEach(visit); return; }
              if (typeof o.articleBody === 'string' && o.articleBody.length > articleBody.length) {
                articleBody = o.articleBody;
              }
              if (o['@graph']) visit(o['@graph']);
            };
            for (const script of document.querySelectorAll('script[type="application/ld+json"]')) {
              try { visit(JSON.parse(script.textContent)); } catch (e) {}
            }
            if (articleBody.length > text.length) text = articleBody;
          }
          return text.slice(0, 200000);
        })()
        """#
}
