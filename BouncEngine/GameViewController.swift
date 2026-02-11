import UIKit
import WebKit
import AVFoundation

final class GameViewController: UIViewController {

    // MARK: - Properties

    private var webView: WKWebView!
    private let gameURL = URL(string: "https://bouncengi.net")!

    // MARK: - Orientation (landscape only)

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var shouldAutorotate: Bool { true }

    // MARK: - Status bar hidden

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Home indicator dimmed (not auto-hidden)
    // This makes the home indicator visible but dimmed. The user must swipe once
    // to "activate" it, then swipe again to actually trigger the gesture.

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var prefersHomeIndicatorAutoHidden: Bool { false }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Match the web app's background color (#0a0a12)
        view.backgroundColor = UIColor(red: 0.039, green: 0.039, blue: 0.071, alpha: 1)

        setupWebView()
        loadGame()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onResumeWebAudio),
            name: .resumeWebAudio,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - WebView Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()

        // ── Data store: default (persists Service Workers, Cache API, IndexedDB, localStorage) ──
        config.websiteDataStore = WKWebsiteDataStore.default()

        // ── Media: allow inline playback, no user-action requirement ──
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // ── JavaScript ──
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // ── AudioContext tracker: injected BEFORE any page script runs ──
        let audioTrackerJS = """
        (function() {
            window._bounceAudioContexts = [];
            var _Orig = window.AudioContext || window.webkitAudioContext;
            if (!_Orig) return;

            window.AudioContext = function AudioContext(opts) {
                var ctx = opts ? new _Orig(opts) : new _Orig();
                window._bounceAudioContexts.push(ctx);
                return ctx;
            };
            window.AudioContext.prototype = _Orig.prototype;

            if (window.webkitAudioContext) {
                window.webkitAudioContext = window.AudioContext;
            }
        })();
        """
        let userScript = WKUserScript(
            source: audioTrackerJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)

        // ── User agent suffix so the site can detect the native wrapper if needed ──
        config.applicationNameForUserAgent = "BouncEngine-iOS"

        // ── Create WKWebView ──
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        // Transparent backing so the background color shows during load
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        // Disable all scroll / bounce / zoom (the game handles its own input)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // Allow Web Inspector in debug builds
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        view.addSubview(webView)

        // Pin to actual view edges (NOT safe area) so content covers the full screen
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    // MARK: - Load

    private func loadGame() {
        webView.load(URLRequest(url: gameURL))
    }

    // MARK: - AudioContext Resume

    /// Evaluates JS to resume every tracked AudioContext that was suspended/interrupted.
    func resumeAudioContext() {
        let js = """
        (function() {
            var list = window._bounceAudioContexts || [];
            for (var i = 0; i < list.length; i++) {
                if (list[i] && (list[i].state === 'suspended' || list[i].state === 'interrupted')) {
                    list[i].resume();
                }
            }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc private func onResumeWebAudio() {
        resumeAudioContext()
    }
}

// MARK: - WKNavigationDelegate

extension GameViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Ensure viewport-fit=cover is set (belt-and-suspenders)
        let js = """
        (function() {
            var meta = document.querySelector('meta[name=viewport]');
            if (meta && meta.content.indexOf('viewport-fit') === -1) {
                meta.setAttribute('content', meta.content + ', viewport-fit=cover');
            }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[WebView] Navigation failed: \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        // Network error — the service worker cache-first strategy should prevent this
        // in most cases, but handle it gracefully.
        print("[WebView] Provisional navigation failed: \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Allow all navigation within bouncengi.net + needed CDNs
        if let url = navigationAction.request.url {
            let host = url.host ?? ""
            if host.isEmpty
                || host.hasSuffix("bouncengi.net")
                || host.hasSuffix("googlesyndication.com")
                || host.hasSuffix("googleads.g.doubleclick.net")
                || host.hasSuffix("google.com")
                || host.hasSuffix("gstatic.com") {
                decisionHandler(.allow)
                return
            }
            // External links → open in Safari
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate

extension GameViewController: WKUIDelegate {

    /// Handle window.open() by loading in the same webview
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
