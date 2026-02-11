import UIKit
@preconcurrency import WebKit
import AVFoundation

final class GameViewController: UIViewController {

    // MARK: - Properties

    private var webView: WKWebView!
    private let gameURL = URL(string: "https://bouncengi.net")!

    // Native loading overlay (mirrors web's .loading-overlay)
    private var nativeLoadingView: UIView!
    private var nativeLoadingLabel: UILabel!
    private var nativeSpinner: UIActivityIndicatorView!
    private var hasHiddenNativeLoading = false

    // Offline retry
    private var navigationRetryCount = 0
    private let maxNavigationRetries = 3

    // MARK: - Orientation (landscape only)

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var shouldAutorotate: Bool { true }

    // MARK: - Status bar hidden

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Home indicator dimmed (not auto-hidden)
    // preferredScreenEdgesDeferringSystemGestures makes the bar visible but dimmed.
    // User must swipe once to "activate" it, then swipe again to trigger the gesture.

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var prefersHomeIndicatorAutoHidden: Bool { false }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(red: 0.094, green: 0.094, blue: 0.094, alpha: 1) // #181818

        setupWebView()
        setupNativeLoadingView()
        loadGame()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onResumeWebAudio),
            name: .resumeWebAudio,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    // MARK: - Native Loading View

    private func setupNativeLoadingView() {
        nativeLoadingView = UIView()
        nativeLoadingView.backgroundColor = UIColor(red: 0.094, green: 0.094, blue: 0.094, alpha: 1) // #181818
        nativeLoadingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nativeLoadingView)

        NSLayoutConstraint.activate([
            nativeLoadingView.topAnchor.constraint(equalTo: view.topAnchor),
            nativeLoadingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            nativeLoadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nativeLoadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Spinner
        nativeSpinner = UIActivityIndicatorView(style: .medium)
        nativeSpinner.color = .white
        nativeSpinner.translatesAutoresizingMaskIntoConstraints = false
        nativeSpinner.startAnimating()
        nativeLoadingView.addSubview(nativeSpinner)

        // Label
        nativeLoadingLabel = UILabel()
        nativeLoadingLabel.text = "Checking for updates..."
        nativeLoadingLabel.textColor = .white
        nativeLoadingLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        nativeLoadingLabel.textAlignment = .center
        nativeLoadingLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeLoadingView.addSubview(nativeLoadingLabel)

        NSLayoutConstraint.activate([
            nativeSpinner.centerXAnchor.constraint(equalTo: nativeLoadingView.centerXAnchor),
            nativeSpinner.centerYAnchor.constraint(equalTo: nativeLoadingView.centerYAnchor, constant: -12),
            nativeLoadingLabel.topAnchor.constraint(equalTo: nativeSpinner.bottomAnchor, constant: 10),
            nativeLoadingLabel.centerXAnchor.constraint(equalTo: nativeLoadingView.centerXAnchor),
            nativeLoadingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nativeLoadingView.leadingAnchor, constant: 20),
            nativeLoadingLabel.trailingAnchor.constraint(lessThanOrEqualTo: nativeLoadingView.trailingAnchor, constant: -20)
        ])
    }

    private func hideNativeLoading(animated: Bool = true) {
        guard !hasHiddenNativeLoading else { return }
        hasHiddenNativeLoading = true

        if animated {
            UIView.animate(withDuration: 0.25, animations: {
                self.nativeLoadingView.alpha = 0
            }, completion: { _ in
                self.nativeLoadingView.removeFromSuperview()
            })
        } else {
            nativeLoadingView.removeFromSuperview()
        }
    }

    // MARK: - WebView Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()

        // ── Persistent data store: keeps Service Workers, Cache API, IndexedDB, localStorage ──
        config.websiteDataStore = WKWebsiteDataStore.default()

        // ── Media: inline playback, no user-action requirement for audio ──
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // ── JavaScript ──
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // ── Message handler for JS → Native communication ──
        config.userContentController.add(self, name: "nativeBridge")

        // ── Injected JS: AudioContext tracker + native loading bridge ──
        // Runs BEFORE any page script. Responsibilities:
        // 1. Tracks AudioContexts for resume-after-interruption
        // 2. Signals DOMContentLoaded (web took over loading UX → hide native splash)
        // 3. Forwards loading text changes to native overlay
        // 4. Signals when web's loading overlay hides (caching complete)
        let injectedJS = """
        (function() {
            // ── AudioContext tracking ──
            window._bounceAudioContexts = [];
            var _Orig = window.AudioContext || window.webkitAudioContext;
            if (_Orig) {
                window.AudioContext = function AudioContext(opts) {
                    var ctx = opts ? new _Orig(opts) : new _Orig();
                    window._bounceAudioContexts.push(ctx);
                    return ctx;
                };
                window.AudioContext.prototype = _Orig.prototype;
                if (window.webkitAudioContext) {
                    window.webkitAudioContext = window.AudioContext;
                }
            }

            // ── Native bridge ──
            function sendToNative(type, data) {
                try {
                    window.webkit.messageHandlers.nativeBridge.postMessage({
                        type: type,
                        data: data || {}
                    });
                } catch(e) {}
            }

            // ── DOMContentLoaded: game container becomes visible (.ready), web loading overlay shows ──
            document.addEventListener('DOMContentLoaded', function() {
                sendToNative('dom_ready', {});

                // Forward loading text changes to native overlay
                var lt = document.getElementById('loadingText');
                if (lt) {
                    sendToNative('loading_text', {text: lt.textContent});
                    new MutationObserver(function() {
                        sendToNative('loading_text', {text: lt.textContent});
                    }).observe(lt, {childList: true, characterData: true, subtree: true});
                }

                // Watch loading overlay — when it gets .hidden class, caching is done
                var lo = document.getElementById('loadingOverlay');
                if (lo) {
                    new MutationObserver(function() {
                        if (lo.classList.contains('hidden')) {
                            sendToNative('web_loading_hidden', {});
                        }
                    }).observe(lo, {attributes: true, attributeFilter: ['class']});
                    // Already hidden (returning visit where cache is complete)
                    if (lo.classList.contains('hidden')) {
                        sendToNative('web_loading_hidden', {});
                    }
                }
            });
        })();
        """

        let userScript = WKUserScript(
            source: injectedJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)

        // ── Do NOT set applicationNameForUserAgent ──
        // The web code checks !window.isNativeApp to decide whether to run SW logic.
        // We intentionally leave isNativeApp unset: the web's service worker should
        // register, check for updates, and cache files exactly like in a browser.

        // ── Create WKWebView ──
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        // Transparent backing so #181818 native bg shows during load
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
        let request = URLRequest(url: gameURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15)
        webView.load(request)
    }

    // MARK: - AudioContext Resume

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

    @objc private func appDidBecomeActive() {
        resumeAudioContext()
    }
}

// MARK: - WKScriptMessageHandler

extension GameViewController: WKScriptMessageHandler {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch type {
            case "dom_ready":
                // Web page DOM loaded → game container is visible → web's loading overlay is showing.
                // The web has taken over the loading UX. Hide native splash after a brief paint delay.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.hideNativeLoading()
                }

            case "loading_text":
                // Mirror web's loading text on native overlay while it's still visible
                if !self.hasHiddenNativeLoading,
                   let data = body["data"] as? [String: Any],
                   let text = data["text"] as? String {
                    self.nativeLoadingLabel?.text = text
                }

            case "web_loading_hidden":
                // Web's loading overlay hidden (caching complete). Ensure native is gone too.
                self.hideNativeLoading()

            default:
                break
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension GameViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Ensure viewport-fit=cover
        let js = """
        (function() {
            var meta = document.querySelector('meta[name=viewport]');
            if (meta && meta.content.indexOf('viewport-fit') === -1) {
                meta.setAttribute('content', meta.content + ', viewport-fit=cover');
            }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        // Reset retry counter on successful navigation
        navigationRetryCount = 0
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[WebView] Navigation failed: \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        // Provisional navigation failed — likely offline on cold start.
        // The service worker from a previous session may need a moment to activate
        // before it can intercept fetch requests and serve from cache.
        // Retry with increasing delays to give the SW time.
        let nsError = error as NSError
        print("[WebView] Provisional navigation failed (\(nsError.code)): \(nsError.localizedDescription)")

        if navigationRetryCount < maxNavigationRetries {
            navigationRetryCount += 1
            let delay = Double(navigationRetryCount) * 1.0
            nativeLoadingLabel?.text = "Connecting..."
            print("[WebView] Retry \(navigationRetryCount)/\(maxNavigationRetries) in \(delay)s")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.loadGame()
            }
        } else {
            // All retries failed — no connection and no cached content
            nativeLoadingLabel?.text = "No connection. Restart when online."
            nativeSpinner?.stopAnimating()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
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
