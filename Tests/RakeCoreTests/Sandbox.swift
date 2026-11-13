import Foundation
import Testing
@testable import RakeCore

/// 所有真删都在 FileManager.temporaryDirectory 下的假主目录里。
final class Sandbox {
    let home: String
    let trash: String
    var trashed: [String] = []
    var now = Date()

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("rake-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        home = realPath(base.path)!
        trash = home + "/.FakeTrash"
        try FileManager.default.createDirectory(atPath: trash, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(atPath: home) }

    func file(_ rel: String, _ text: String = "x", ageDays: Double = 0) {
        let p = home + "/" + rel
        try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: p, contents: Data(text.utf8))
        if ageDays > 0 { age(rel, ageDays) }
    }
    func dir(_ rel: String) { try? FileManager.default.createDirectory(atPath: home + "/" + rel, withIntermediateDirectories: true) }
    func age(_ rel: String, _ days: Double) {
        let d = Date().addingTimeInterval(-days * 86400)
        try? FileManager.default.setAttributes([.modificationDate: d], ofItemAtPath: home + "/" + rel)
    }
    func exists(_ rel: String) -> Bool { lstatInfo(home + "/" + rel) != nil }

    static var strings: Strings = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try! Strings.load(root.appendingPathComponent("i18n/strings.json"), lang: "en")
    }()

    func engine(rules: [Rule]? = nil, ttl: TimeInterval = 600, volumes: VolumeInfo? = nil) -> Engine {
        var c = EngineConfig(home: home, stateDir: home + "/.rake-state", strings: Sandbox.strings)
        if let rules { c.rules = rules }
        c.scanSystem = false
        c.planTTL = ttl
        c.minStoneGB = 0
        let v = volumes ?? VolumeInfo(total: 100 << 30, free: 10 << 30, dataUsed: 80 << 30, vmUsed: 2 << 30, swapUsed: 1 << 30, uptimeDays: 3)
        c.volumes = { v }
        c.now = { [unowned self] in self.now }
        c.trasher = { [unowned self] url in  // 假废纸篓：挪进沙盒里的 .FakeTrash
            let dst = self.trash + "/" + url.lastPathComponent
            try FileManager.default.moveItem(atPath: url.path, toPath: dst)
            self.trashed.append(url.path)
        }
        return Engine(c)
    }

    /// 测试用规则：auto 档直接删，decide 档进废纸篓。
    var rules: [Rule] {
        [Rule(id: "tc", tier: .auto, kind: .caches) { c in c.g("Library/Caches/TestApp/*") },
         Rule(id: "td", tier: .decide, kind: .content) { c in c.g("Downloads/old-*") },
         Rule(id: "tl", tier: .later, kind: .caches) { c in c.g("Library/Caches/Later/*") }]
    }
}
