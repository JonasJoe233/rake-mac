import Foundation
import RakeCore

/// App 包里在 Contents/Resources/{web,i18n}；swift run 时退回仓库目录。
enum Resources {
    static var root: URL {
        if let r = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: r.appendingPathComponent("web/app.html").path) {
            return r
        }
        if let env = ProcessInfo.processInfo.environment["RAKE_RESOURCES"] { return URL(fileURLWithPath: env) }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("web/app.html").path) { return dir }
            dir.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
    static var web: URL { root.appendingPathComponent("web") }
    static var stringsURL: URL { root.appendingPathComponent("i18n/strings.json") }
    static func strings() throws -> Strings { try Strings.load(stringsURL) }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? (try? String(contentsOf: root.appendingPathComponent("VERSION")).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "dev"
    }
}
