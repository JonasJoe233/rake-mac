import AppKit
import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    func makeCoordinator() -> Nav { Nav() }

    func makeNSView(context: Context) -> WKWebView {
        let b = Bridge.shared
        let cfg = WKWebViewConfiguration()
        let uc = cfg.userContentController
        uc.addScriptMessageHandler(b, contentWorld: .page, name: "rake")
        uc.add(b, name: "rakeLog")
        let dict = b.strings.map { String(decoding: $0.json, as: UTF8.self) } ?? "{}"
        let lang = b.strings?.lang ?? "en"
        let boot = """
        window.RAKE_I18N=\(dict);window.RAKE_LANG="\(lang)";window.RAKE_VERSION="\(Resources.version)";
        (function(){const p=(l,m)=>{try{webkit.messageHandlers.rakeLog.postMessage({level:l,msg:String(m)})}catch(e){}};
        const ce=console.error.bind(console),cw=console.warn.bind(console);
        console.error=(...a)=>{p("error",a.join(" "));ce(...a)};console.warn=(...a)=>{p("warn",a.join(" "));cw(...a)};
        addEventListener("error",e=>p("error",e.message+" @"+e.filename+":"+e.lineno));
        addEventListener("unhandledrejection",e=>p("error","unhandled rejection: "+(e.reason&&e.reason.message||e.reason)));})();
        """
        uc.addUserScript(WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.setValue(false, forKey: "drawsBackground")  // 加载前不闪白
        b.webView = wv
        let page = Resources.web.appendingPathComponent("app.html")
        wv.loadFileURL(page, allowingReadAccessTo: Resources.web)
        if let s = b.snapshot { s.prepare(wv) }
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    /// 只允许加载 App 自己的 web 目录；外链交给默认浏览器。
    final class Nav: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            if url.isFileURL && url.standardizedFileURL.path.hasPrefix(Resources.web.standardizedFileURL.path) {
                return decisionHandler(.allow)
            }
            if ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
}
