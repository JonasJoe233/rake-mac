import AppKit
import RakeCore
import WebKit

/// JS bridge：页面里 window.webkit.messageHandlers.rake.postMessage({op, body}) 返回 Promise<String(JSON)>。
/// 替换 v7 的 /api/scan、/api/rescan、/api/plan、/api/apply。引擎调用都在一条串行队列上，扫描和删除天然不并发。
final class Bridge: NSObject, WKScriptMessageHandlerWithReply, WKScriptMessageHandler {
    static let shared = Bridge()

    let strings: Strings?
    let engine: Engine?
    let loadError: String?
    let work = DispatchQueue(label: "rake.engine")
    private var scanJSON: String?
    private var waiting: [(String?, String?) -> Void] = []
    private var scanning = false
    weak var webView: WKWebView?
    var consoleErrors: [String] = []
    let snapshot = Snapshot.fromArgs()

    override init() {
        do {
            let s = try Resources.strings()
            strings = s
            engine = Engine(.live(strings: s))
            loadError = nil
        } catch {
            strings = nil; engine = nil
            loadError = "\(error)"
        }
        super.init()
    }

    static func encode<T: Encodable>(_ v: T) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: (try? e.encode(v)) ?? Data("{}".utf8), as: UTF8.self)
    }

    // MARK: scan 缓存：启动就开始扫，页面要的时候等它

    func startScan() {
        guard let engine, !scanning else { return }
        scanning = true
        work.async {
            let json = Bridge.encode(engine.scan())
            DispatchQueue.main.async {
                self.scanning = false
                self.scanJSON = json
                self.snapshot?.save(json, "scan.json")
                let w = self.waiting; self.waiting = []
                w.forEach { $0(json, nil) }
            }
        }
    }

    func withScan(_ reply: @escaping (String?, String?) -> Void) {
        if let j = scanJSON { return reply(j, nil) }
        waiting.append(reply)
        startScan()
    }

    // MARK: WKScriptMessageHandlerWithReply

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let engine, let msg = message.body as? [String: Any], let op = msg["op"] as? String else {
            return replyHandler(nil, loadError ?? "bad message")
        }
        let body = msg["body"] as? [String: Any] ?? [:]
        let ids = (body["ids"] as? [Any])?.compactMap { $0 as? String } ?? []
        let reply: (String?, String?) -> Void = { r, e in replyHandler(r, e) }
        switch op {
        case "scan":
            withScan(reply)
        case "rescan":
            scanJSON = nil
            withScan { j, e in reply(j == nil ? nil : "{}", e) }
        case "plan":
            work.async {
                let r: (String?, String?)
                do { r = (Bridge.encode(try engine.plan(ids: ids)), nil) } catch { r = (nil, "\(error)") }
                DispatchQueue.main.async {
                    if let j = r.0 { self.snapshot?.save(j, "plan.json") }
                    reply(r.0, r.1)
                }
            }
        case "apply":
            guard snapshot == nil else { return reply(nil, "apply is disabled in --snapshot mode") }
            let token = body["token"] as? String ?? ""
            work.async {
                let r: (String?, String?)
                do { r = (Bridge.encode(try engine.apply(ids: ids, token: token)), nil) } catch { r = (nil, "\(error)") }
                DispatchQueue.main.async {
                    if r.0 != nil { self.scanJSON = nil }  // 删过东西，下次要重扫
                    reply(r.0, r.1)
                }
            }
        case "event":
            reply("{}", nil)
            if let name = body["name"] as? String, let wv = webView { snapshot?.event(name, wv, self) }
        default:
            reply(nil, "unknown op \(op)")
        }
    }

    /// rakeLog：页面里的 console.error / 未捕获异常。
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any] else { return }
        let line = "[\(m["level"] as? String ?? "log")] \(m["msg"] as? String ?? "")"
        consoleErrors.append(line)
        FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
    }
}
