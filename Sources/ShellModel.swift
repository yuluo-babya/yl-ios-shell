import UIKit
import WebKit
import Combine
import AudioToolbox

final class ShellModel: NSObject, ObservableObject {
    @Published var progress: Double = 0

    let webView: WKWebView
    private var observation: NSKeyValueObservation?

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = WKWebsiteDataStore.default()

        let controller = WKUserContentController()
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let bridge = """
        window.__deviceId = "__DEVICE_ID__";
        window.__appPlatform = "ios";
        window.NativeBridge = {
            getAndroidId: function () { return window.__deviceId; },
            getDeviceId: function () { return window.__deviceId; },
            getModel: function () { return "iPhone"; },
            getPlatform: function () { return "ios"; },
            vibrate: function () { window.webkit.messageHandlers.app.postMessage({ action: "vibrate" }); },
            openUrl: function (u) { window.webkit.messageHandlers.app.postMessage({ action: "openUrl", url: String(u) }); },
            toast: function (m) { window.webkit.messageHandlers.app.postMessage({ action: "toast", message: String(m) }); }
        };
        """
        controller.addUserScript(WKUserScript(source: bridge.replacingOccurrences(of: "__DEVICE_ID__", with: deviceId), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        controller.add(self, name: "app")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        observation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
            DispatchQueue.main.async {
                self?.progress = Double(view.estimatedProgress)
            }
        }

        loadStart()
    }

    private func loadStart() {
        let info = Bundle.main.infoDictionary ?? [:]
        if let raw = info["YLStartURL"] as? String, !raw.isEmpty, let url = URL(string: raw), url.scheme != nil {
            webView.load(URLRequest(url: url))
            return
        }
        let page = (info["YLStartPage"] as? String) ?? "index.html"
        let folder = (info["YLWebDir"] as? String) ?? "www"
        let ext = (page as NSString).pathExtension
        let name = (page as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? nil : ext, subdirectory: folder) else { return }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}

extension ShellModel: WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progress = 1.0
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        progress = 1.0
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        progress = 1.0
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        if navigationAction.targetFrame == nil && (scheme == "http" || scheme == "https") {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        if ["http", "https", "file", "about", "data", "blob"].contains(scheme) {
            decisionHandler(.allow)
            return
        }
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let host = topViewController() else {
            completionHandler()
            return
        }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        host.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let host = topViewController() else {
            completionHandler(false)
            return
        }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        host.present(alert, animated: true)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "vibrate":
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        case "openUrl":
            if let raw = body["url"] as? String, let url = URL(string: raw), url.scheme != nil {
                UIApplication.shared.open(url)
            }
        case "toast":
            if let text = body["message"] as? String, let host = topViewController() {
                let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default))
                host.present(alert, animated: true)
            }
        default:
            break
        }
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: { $0.isKeyWindow })
            ?? scenes.first?.windows.first
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
