import Foundation
import Testing
@testable import RakeCore

@Suite("scan 与通用规则") struct ScanTests {
    @Test("scan 输出 v7 的 STONES 结构")
    func structure() throws {
        let sb = try Sandbox()
        sb.file(".npm/_cacache/index-v5/aa", String(repeating: "n", count: 40000))
        sb.file("Library/Caches/pip/http/x", String(repeating: "p", count: 20000))
        sb.file("Documents/report.txt", String(repeating: "d", count: 9000))
        sb.file("Library/Keychains/k")
        let r = sb.engine().scan()
        let ids = r.stones.map { $0.id }
        #expect(ids.first == "free")
        #expect(Set(ids).count == ids.count)
        #expect(["npm", "pip", "docs", "sysdata", "swap"].allSatisfy(ids.contains))
        for s in r.stones where s.tier?.pickable == true { #expect(s.why?.isEmpty == false && s.cmd?.isEmpty == false) }
        for s in r.stones where s.kind == .content { #expect(s.tier == nil || ["dl", "trash"].contains(s.id)) }
        #expect(r.stones.allSatisfy { $0.size >= 0 })
        #expect(r.stone("swap")?.tier == .manual)
        #expect(r.keep.count >= 8)
        let json = String(decoding: try JSONEncoder().encode(r), as: UTF8.self)
        for k in ["\"scanned_at\"", "\"grow_base\"", "\"stones\"", "\"keep\"", "\"log\"", "\"denied_count\""] { #expect(json.contains(k)) }
        #expect(sb.exists(".rake-state/snapshots"))
    }

    @Test("通用规则在假主目录里各自命中：npm / pip / uv / brew / vsix / crx / upd / ext / dl")
    func standardRules() throws {
        let sb = try Sandbox()
        sb.file(".npm/_cacache/x"); sb.file("Library/Caches/pip/x"); sb.file(".cache/uv/x")
        sb.file("Library/Caches/Homebrew/downloads/x.bottle.tar.gz")
        sb.file("Library/Application Support/Code/CachedExtensionVSIXs/a.vsix"); sb.age("Library/Application Support/Code/CachedExtensionVSIXs", 1)
        sb.file("Library/Application Support/Google/GoogleUpdater/crx_cache/c", ageDays: 1)
        sb.file("Library/Caches/com.example.app/org.sparkle-project.Sparkle/u.zip"); sb.age("Library/Caches/com.example.app/org.sparkle-project.Sparkle", 1)
        sb.dir("Library/Caches/com.fresh.app/org.sparkle-project.Sparkle")  // 6 小时内改过，跳过
        sb.dir(".vscode/extensions/ms-python.python-2026.1.0"); sb.dir(".vscode/extensions/ms-python.python-2026.8.0")
        sb.dir(".vscode/extensions/handmade.thing-1.0.0")
        sb.file(".vscode/extensions/extensions.json",
                #"[{"identifier":{"id":"ms-python.python"},"relativeLocation":"ms-python.python-2026.8.0"}]"#)
        sb.file("Downloads/old-big.dmg", ageDays: 40); sb.file("Downloads/new.dmg")
        var rules = Rules.standard
        for id in ["dl", "upd"] { if let i = rules.firstIndex(where: { $0.id == id }) { rules[i].minSize = 0 } }  // 不在测试里造 150 MB、1 MB 的文件
        let e = sb.engine(rules: rules)
        let p = try e.plan(ids: ["npm", "pip", "uv", "brew", "vsix", "crx", "upd", "ext", "dl"])
        let got = Dictionary(uniqueKeysWithValues: p.items.map { ($0.id, $0.paths.map { $0.path }) })
        #expect(got["npm"] == ["~/.npm/_cacache"])
        #expect(got["pip"] == ["~/Library/Caches/pip"])
        #expect(got["uv"] == ["~/.cache/uv"])
        #expect(got["brew"] == ["~/Library/Caches/Homebrew/downloads"])
        #expect(got["vsix"] == ["~/Library/Application Support/Code/CachedExtensionVSIXs"])
        #expect(got["crx"] == ["~/Library/Application Support/Google/GoogleUpdater/crx_cache/c"])
        #expect(got["upd"] == ["~/Library/Caches/com.example.app/org.sparkle-project.Sparkle"])
        #expect(got["ext"] == ["~/.vscode/extensions/ms-python.python-2026.1.0"])
        #expect(got["dl"] == ["~/Downloads/old-big.dmg"])
        #expect(p.items.first { $0.id == "dl" }?.method == .trash)
        _ = try e.apply(ids: p.ids, token: p.token)
        #expect(sb.exists(".npm") && sb.exists("Library/Caches") && sb.exists(".vscode/extensions/ms-python.python-2026.8.0"))
        #expect(sb.exists(".vscode/extensions/handmade.thing-1.0.0"))
        #expect(sb.exists("Library/Caches/com.fresh.app/org.sparkle-project.Sparkle"))
        #expect(sb.exists(".FakeTrash/old-big.dmg") && sb.exists("Downloads/new.dmg"))
    }

    @Test("脱敏：通用规则只有这几条，每台 Mac 都可能有")
    func noPersonalRules() {
        #expect(Rules.standard.map { $0.id } == ["upd", "crx", "vsix", "ext", "npm", "pip", "uv", "brew", "dl"])
        #expect(Rules.standard.allSatisfy { $0.tier != .later && $0.tier != .manual })
    }

    @Test("Walker 读不到的目录跳过并计数")
    func deniedCounted() throws {
        let sb = try Sandbox()
        sb.file("Library/Caches/Locked/inner/x")
        chmod(sb.home + "/Library/Caches/Locked", 0)
        defer { chmod(sb.home + "/Library/Caches/Locked", 0o755) }
        let w = Walker.walk(sb.home + "/Library", recordDepth: 1)
        #expect(w.denied >= 1)
    }
}

@Suite("文案") struct StringsTests {
    @Test("en 和 zh-Hans 的 key 完全一致，规则和卵石都有文案")
    func parity() throws {
        let all = try JSONDecoder().decode([String: [String: String]].self, from: Sandbox.strings.json)
        let en = Set(all["en"]!.keys), zh = Set(all["zh-Hans"]!.keys)
        #expect(en == zh)
        for r in Rules.standard { for f in ["label", "why", "cmd"] { #expect(en.contains("rule.\(r.id).\(f)")) } }
        for k in Guard.standardKeep { #expect(en.contains("keep." + k.key) && en.contains("keep.\(k.key).why")) }
    }

    @Test("中文系统切简体中文，其他一律英文")
    func language() {
        #expect(Strings.language(["zh-Hans-CN"]) == "zh-Hans" || ProcessInfo.processInfo.environment["RAKE_LANG"] != nil)
        #expect(Strings.language(["zh-Hant-TW"]) == "zh-Hans" || ProcessInfo.processInfo.environment["RAKE_LANG"] != nil)
        #expect(Strings.language(["fr-FR"]) == "en" || ProcessInfo.processInfo.environment["RAKE_LANG"] != nil)
    }
}
