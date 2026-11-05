import AppKit
import WebKit

/// --snapshot <目录>：扫描出图 → map.png；勾 auto 档、打开 dry-run 清单 → plan.png；写 console.txt 后退出。
/// 只截图，不点确认。apply 在这个模式下被 Bridge 直接拒绝。
final class Snapshot {
    let dir: URL
    private var stage = 0

    init(dir: URL) { self.dir = dir }

    static func fromArgs() -> Snapshot? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--snapshot"), i + 1 < a.count else { return nil }
        let d = URL(fileURLWithPath: a[i + 1])
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return Snapshot(dir: d)
    }

    func save(_ text: String, _ name: String) {
        try? text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func prepare(_ wv: WKWebView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            wv.window?.setContentSize(NSSize(width: 1440, height: 900))
            wv.window?.center()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 240) { self.finish("timeout") }
    }

    func event(_ name: String, _ wv: WKWebView, _ bridge: Bridge) {
        if name == "rendered" && stage == 0 {
            stage = 1
            shoot(wv, "map.png") {
                wv.evaluateJavaScript(#"document.querySelector('[data-all="auto"]')?.click(); document.getElementById('goDirect').click();"#)
            }
        } else if name == "planShown" && stage == 1 {
            stage = 2
            shoot(wv, "plan.png") { self.finish("ok") }
        }
    }

    private func shoot(_ wv: WKWebView, _ name: String, then: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            wv.takeSnapshot(with: nil) { img, err in
                if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: self.dir.appendingPathComponent(name))
                } else {
                    self.save("\(String(describing: err))", name + ".error.txt")
                }
                then()
            }
        }
    }

    private func finish(_ status: String) {
        let errs = Bridge.shared.consoleErrors
        save("status: \(status)\nconsole messages: \(errs.count)\n" + errs.joined(separator: "\n") + "\n", "console.txt")
        NSApp.terminate(nil)
    }
}
