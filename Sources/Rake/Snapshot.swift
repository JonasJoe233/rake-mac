import AppKit
import WebKit

/// --snapshot <目录>：自动走一遍界面并截图，然后退出。
/// 真实主目录下：扫描出图 → map.png；勾 auto 档、打开清单 → plan.png。apply 被 Bridge 拒绝，不会删东西。
/// 加 --test-home <临时目录> 时继续往下走：点确认 → progress.png；清完 → done.png；后台重扫完 → rescanned.png。
/// 只删临时目录里造的假文件。每一步另存一张带窗口边框的 window-*.png，用来看标题栏。
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
        let full = Bridge.testHome != nil
        switch (name, stage) {
        case ("rendered", 0):
            stage = 1
            shoot(wv, "map") {
                wv.evaluateJavaScript(#"document.querySelector('[data-all="auto"]')?.click(); document.getElementById('goDirect').click();"#)
            }
        case ("planShown", 1):
            stage = 2
            shoot(wv, "plan") {
                if full { wv.evaluateJavaScript("document.querySelector('[data-confirm]')?.click()") } else { self.finish("ok") }
            }
        case ("applyStarted", 2):
            stage = 3
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.shoot(wv, "progress", delay: 0) {} }
        case ("applyDone", 3):
            stage = 4
            shoot(wv, "done", delay: 0.5) {}
        case ("rescanned", 4):
            stage = 5
            shoot(wv, "rescanned", delay: 1.2) { self.finish("ok") }
        default:
            break
        }
    }

    private func shoot(_ wv: WKWebView, _ name: String, delay: Double = 0.8, then: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let wid = wv.window?.windowNumber {  // 带标题栏的整窗截图，看顶部有没有白条
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", "\(wid)", self.dir.appendingPathComponent("window-\(name).png").path]
                try? p.run(); p.waitUntilExit()
            }
            wv.takeSnapshot(with: nil) { img, err in
                if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: self.dir.appendingPathComponent(name + ".png"))
                } else {
                    self.save("\(String(describing: err))", name + ".error.txt")
                }
                then()
            }
        }
    }

    private func finish(_ status: String) {
        let errs = Bridge.shared.consoleErrors
        save("status: \(status)\nstage: \(stage)\nconsole messages: \(errs.count)\n" + errs.joined(separator: "\n") + "\n", "console.txt")
        NSApp.terminate(nil)
    }
}
