import AppKit
import SwiftUI

struct RakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup(Bridge.shared.strings?.t("app.name") ?? "Rake") {
            WebView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { CommandGroup(replacing: .newItem) {} }
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
