import UIKit
import WebKit

/// Écran unique : une WKWebView qui affiche l'interface (index.html) et reçoit les appels de window.Native.
final class DashboardViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private let bridge = Bridge()
    private let ucc = WKUserContentController()

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func loadView() {
        let conf = WKWebViewConfiguration()
        ucc.add(WeakScriptHandler(self), name: "native")
        conf.userContentController = ucc
        bridge.onSettingsImported = { [weak self] in self?.loadPage() }
        bridge.onCfgChanged = { [weak self] in DispatchQueue.main.async { self?.installShim() } }

        let wv = WKWebView(frame: .zero, configuration: conf)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        let bg = UIColor(red: 15 / 255, green: 17 / 255, blue: 20 / 255, alpha: 1)
        wv.isOpaque = true
        wv.backgroundColor = bg
        wv.scrollView.backgroundColor = bg
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.minimumZoomScale = 1
        wv.scrollView.maximumZoomScale = 1
        wv.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView = wv
        bridge.webView = wv
        view = wv
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadPage()
    }

    /// (Ré)installe le pont avec l'état du moment (réglages, batterie…) : une page rechargée, même par elle-même, le retrouve à jour.
    private func installShim() {
        ucc.removeAllUserScripts()
        ucc.addUserScript(WKUserScript(source: bridge.shimSource(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// Charge l'interface fournie avec l'appli.
    func loadPage() {
        installShim()
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html") else {
            webView.loadHTMLString("<body style='background:#0f1114;color:#ff7a70;font:20px sans-serif;padding:40px'>index.html introuvable dans l'appli.</body>", baseURL: nil)
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        bridge.handle(message.body, reloadPage: { [weak self] in self?.loadPage() })
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        bridge.pushState()
    }

    // iOS peut arrêter le processus de la page quand il manque de mémoire : on la recharge.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadPage()
    }
}

/// Évite que la WKUserContentController garde le contrôleur en vie (cycle de références).
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
