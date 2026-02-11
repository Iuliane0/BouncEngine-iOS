import UIKit
@preconcurrency import WebKit
import AVFoundation

final class GameViewController: UIViewController {

    // MARK: - Properties

    private var webView: WKWebView!
    private let gameURL = URL(string: "https://bouncengi.net")!

    // Minimal color-matched splash — hides the blank WKWebView initialization frame.
    // No text, no spinners. The web has its own full loading UX.
    private var splashView: UIView!
    private var splashHidden = false

    // Offline retry
    private var retryCount = 0
    private let maxRetries = 3

    // MARK: - Orientation (landscape only)

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var shouldAutorotate: Bool { true }
    override var prefersStatusBarHidden: Bool { true }

    // Home indicator dimmed (double-swipe to activate)
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var prefersHomeIndicatorAutoHidden: Bool { false }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.094, green: 0.094, blue: 0.094, alpha: 1)

        setupWebView()
        setupSplash()
        loadGame()

        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onResumeWebAudio),
                                               name: .resumeWebAudio, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    // MARK: - Splash (just a colored view, hides when web paints)

    private func setupSplash() {
        splashView = UIView()
        splashView.backgroundColor = UIColor(red: 0.094, green: 0.094, blue: 0.094, alpha: 1)
        splashView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splashView)
        NSLayoutConstraint.activate([
            splashView.topAnchor.constraint(equalTo: view.topAnchor),
            splashView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            splashView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splashView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func hideSplash() {
        guard !splashHidden else { return }
        splashHidden = true
        UIView.animate(withDuration: 0.2, animations: {
            self.splashView.alpha = 0
        }, completion: { _ in
            self.splashView.removeFromSuperview()
        })
    }

    // MARK: - WebView Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // App-Bound Domains: enables full Service Worker + Cache API support in WKWebView
        config.limitsNavigationsToAppBoundDomains = true

        // AudioContext tracker — keeps references so we can resume after interruption
        let injectedJS = """
        (function() {
            window._bounceAudioContexts = [];
            var _Orig = window.AudioContext || window.webkitAudioContext;
            if (_Orig) {
                window.AudioContext = function AudioContext(opts) {
                    var ctx = opts ? new _Orig(opts) : new _Orig();
                    window._bounceAudioContexts.push(ctx);
                    return ctx;
                };
                window.AudioContext.prototype = _Orig.prototype;
                if (window.webkitAudioContext) window.webkitAudioContext = window.AudioContext;
            }
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: injectedJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )

        // Fix font-display: the web uses @font-face for "Raylib" without font-display,
        // defaulting to "block" which makes loading text INVISIBLE while the font downloads.
        // Inject a replacement @font-face at documentEnd so it overrides the page's rule.
        let fontFixJS = """
        (function() {
            var s = document.createElement('style');
            s.textContent = '@font-face { font-family: "Raylib"; src: url("/raylib.ttf") format("opentype"); font-display: swap; }';
            document.head.appendChild(s);
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: fontFixJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    // MARK: - Load

    private func loadGame() {
        webView.load(URLRequest(url: gameURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15))
    }

    // MARK: - Audio

    func resumeAudioContext() {
        webView?.evaluateJavaScript("""
            (function() {
                var list = window._bounceAudioContexts || [];
                for (var i = 0; i < list.length; i++) {
                    if (list[i] && (list[i].state === 'suspended' || list[i].state === 'interrupted')) {
                        list[i].resume();
                    }
                }
            })();
        """, completionHandler: nil)
    }

    @objc private func onResumeWebAudio() { resumeAudioContext() }
    @objc private func appDidBecomeActive() { resumeAudioContext() }
}

// MARK: - WKNavigationDelegate

extension GameViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        retryCount = 0

        // Hide splash once the web page has rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.hideSplash()
        }

        // Ensure viewport-fit=cover
        webView.evaluateJavaScript("""
            (function() {
                var m = document.querySelector('meta[name=viewport]');
                if (m && m.content.indexOf('viewport-fit') === -1)
                    m.setAttribute('content', m.content + ', viewport-fit=cover');
            })();
        """, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[WebView] Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Offline cold start — SW may need a moment to activate. Retry with backoff.
        print("[WebView] Provisional navigation failed: \(error.localizedDescription)")
        if retryCount < maxRetries {
            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(retryCount)) { [weak self] in
                self?.loadGame()
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        let host = url.host ?? ""
        if host.isEmpty || host.hasSuffix("bouncengi.net")
            || host.hasSuffix("googlesyndication.com") || host.hasSuffix("doubleclick.net")
            || host.hasSuffix("google.com") || host.hasSuffix("gstatic.com") {
            decisionHandler(.allow)
        } else {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}

// MARK: - WKUIDelegate

extension GameViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}
