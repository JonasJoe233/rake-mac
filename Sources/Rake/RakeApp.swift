import AppKit
import SwiftUI

struct RakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup(Bridge.shared.strings?.t("app.name") ?? "Rake") {
            WebView()
                .frame(minWidth: 900, minHeight: 600)
                .ignoresSafeArea()
                .background(Color(nsColor: Window.ground))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

/// 原生窗口：标题栏透明，内容铺满整个窗口，底色和页面一样是沙地色，只留红黄绿按钮。
enum Window {
    static let ground = NSColor(srgbRed: 0xef / 255, green: 0xeb / 255, blue: 0xe1 / 255, alpha: 1)

    static func style(_ w: NSWindow?) {
        guard let w else { return }
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.styleMask.insert(.fullSizeContentView)
        w.backgroundColor = ground
        w.isOpaque = true
        w.appearance = NSAppearance(named: .aqua)  // 页面只有浅色一套，窗口跟着用浅色
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)  // swift run 时也有 Dock 图标和菜单
        NSApp.activate(ignoringOtherApps: true)
        Bridge.shared.startScan()           // 不等页面，先开始扫描
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
