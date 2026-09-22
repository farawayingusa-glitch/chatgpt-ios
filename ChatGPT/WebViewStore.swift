import UIKit
import WebKit

extension Notification.Name {
    static let chatGPTPageReady = Notification.Name("ChatGPTPageReady")
}

private final class PageReadyBridge: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "pageReady" else { return }
        NotificationCenter.default.post(name: .chatGPTPageReady, object: nil)
    }
}

/// Owns the single web view for the lifetime of the app. Creating and loading it
/// during application launch starts WebKit before the scene finishes appearing,
/// and keeping it alive avoids rebuilding the whole ChatGPT page unnecessarily.
final class WebViewStore {
    static let shared = WebViewStore()

    let webView: WKWebView

    private let homeURL = URL(string: "https://chatgpt.com")!
    private let pageReadyBridge = PageReadyBridge()

    private init() {
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: Self.systemThemeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        contentController.addUserScript(WKUserScript(
            source: Self.pageReadyScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        contentController.add(pageReadyBridge, name: "pageReady")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.suppressesIncrementalRendering = false
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.safariUserAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
    }

    func loadIfNeeded() {
        guard webView.url == nil, !webView.isLoading else { return }
        webView.load(URLRequest(url: homeURL, cachePolicy: .useProtocolCachePolicy))
    }

    func reloadOrLoadHome() {
        if webView.url == nil {
            webView.load(URLRequest(url: homeURL, cachePolicy: .useProtocolCachePolicy))
        } else {
            webView.reload()
        }
    }

    func applySystemTheme() {
        webView.evaluateJavaScript("window.__chatGPTWrapperApplyTheme?.();")
    }

    private static let safariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"

    /// ChatGPT uses the `theme` local-storage key. Setting it before the site's
    /// own theme bootstrap runs prevents a light flash and makes the web page
    /// follow iOS appearance changes, rather than only changing the status bar.
    private static let systemThemeScript = #"""
    (() => {
      const host = window.location.hostname.toLowerCase();
      if (host !== 'chatgpt.com' && !host.endsWith('.chatgpt.com')) return;

      const media = window.matchMedia('(prefers-color-scheme: dark)');
      const apply = () => {
        try { window.localStorage.setItem('theme', 'system'); } catch (_) {}
        const root = document.documentElement;
        if (!root) return;
        root.classList.toggle('dark', media.matches);
        root.style.colorScheme = media.matches ? 'dark' : 'light';
      };

      window.__chatGPTWrapperApplyTheme = apply;
      apply();
      document.addEventListener('DOMContentLoaded', apply, { once: true });
      if (media.addEventListener) media.addEventListener('change', apply);
      else if (media.addListener) media.addListener(apply);
    })();
    """#

    /// Signals as soon as the real composer becomes visible. The native launch
    /// placeholder can then fade out without waiting for unrelated resources.
    private static let pageReadyScript = #"""
    (() => {
      const host = window.location.hostname.toLowerCase();
      if (host !== 'chatgpt.com' && !host.endsWith('.chatgpt.com')) return;
      if (window.__chatGPTWrapperReadyObserverInstalled) return;
      window.__chatGPTWrapperReadyObserverInstalled = true;

      let sent = false;
      const selector = '#prompt-textarea, [data-testid="composer-input"], main textarea, main [contenteditable="true"]';
      const notifyIfReady = () => {
        if (sent) return;
        const composer = document.querySelector(selector);
        if (!composer) return;
        const rect = composer.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0) return;
        sent = true;
        window.webkit.messageHandlers.pageReady.postMessage(true);
        observer.disconnect();
      };

      const observer = new MutationObserver(notifyIfReady);
      const start = () => {
        if (!document.documentElement) return;
        observer.observe(document.documentElement, { childList: true, subtree: true });
        notifyIfReady();
      };

      start();
      document.addEventListener('DOMContentLoaded', notifyIfReady, { once: true });
      window.setTimeout(notifyIfReady, 250);
      window.setTimeout(notifyIfReady, 1000);
      window.setTimeout(notifyIfReady, 2500);
    })();
    """#
}
