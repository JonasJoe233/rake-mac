import Foundation
import Testing
@testable import RakeCore

@Suite("plan / apply") struct PlanApplyTests {
    @Test("两档删除方式：auto 直接删，decide 移进废纸篓")
    func methods() throws {
        let sb = try Sandbox()
        sb.file("Library/Caches/TestApp/a.bin"); sb.file("Library/Caches/TestApp/b.bin")
        sb.file("Downloads/old-installer.dmg")
        let e = sb.engine(rules: sb.rules)
        let p = try e.plan(ids: ["tc", "td"])
        #expect(p.items.first { $0.id == "tc" }?.method == .remove)
        #expect(p.items.first { $0.id == "td" }?.method == .trash)
        #expect(p.items.flatMap { $0.paths }.count == 3)
        let r = try e.apply(ids: ["tc", "td"], token: p.token)
        #expect(r.done == ["tc", "td"])
        #expect(!sb.exists("Library/Caches/TestApp/a.bin") && !sb.exists("Library/Caches/TestApp/b.bin"))
        #expect(!sb.exists("Downloads/old-installer.dmg"))
        #expect(sb.exists(".FakeTrash/old-installer.dmg"))           // decide 档进了废纸篓
        #expect(sb.trashed == [sb.home + "/Downloads/old-installer.dmg"])
        #expect(!sb.exists(".FakeTrash/a.bin"))                      // auto 档没走废纸篓
    }

    @Test("token 一次性：用过就失效，失败也作废")
    func tokenSingleUse() throws {
        let sb = try Sandbox()
        sb.file("Library/Caches/TestApp/a.bin")
        let e = sb.engine(rules: sb.rules)
        let p = try e.plan(ids: ["tc"])
        _ = try e.apply(ids: ["tc"], token: p.token)
        #expect(throws: RakeError.tokenInvalid) { try e.apply(ids: ["tc"], token: p.token) }
        #expect(throws: RakeError.tokenInvalid) { try e.apply(ids: ["tc"], token: "made-up") }
        let p2 = try e.plan(ids: ["tc"])
        #expect(throws: RakeError.idsMismatch) { try e.apply(ids: ["td"], token: p2.token) }
        #expect(throws: RakeError.tokenInvalid) { try e.apply(ids: ["tc"], token: p2.token) }  // ids 不一致那次已作废
    }

    @Test("token 过期失效，什么都不删")
    func tokenExpiry() throws {
        let sb = try Sandbox()
        sb.file("Library/Caches/TestApp/a.bin")
        let e = sb.engine(rules: sb.rules, ttl: 600)
        let p = try e.plan(ids: ["tc"])
        sb.now = sb.now.addingTimeInterval(601)
        #expect(throws: RakeError.tokenExpired) { try e.apply(ids: ["tc"], token: p.token) }
        #expect(sb.exists("Library/Caches/TestApp/a.bin"))
    }

    @Test("清单外的路径不删：dry-run 之后才出现的文件、别的规则的文件都留着")
    func outsideListRefused() throws {
        let sb = try Sandbox()
        sb.file("Library/Caches/TestApp/a.bin")
        sb.file("Downloads/old-keep.zip")
        let e = sb.engine(rules: sb.rules)
        let p = try e.plan(ids: ["tc"])
        sb.file("Library/Caches/TestApp/late.bin")   // 确认之后才冒出来
        let r = try e.apply(ids: ["tc"], token: p.token)
        #expect(r.done == ["tc"])
        #expect(!sb.exists("Library/Caches/TestApp/a.bin"))
        #expect(sb.exists("Library/Caches/TestApp/late.bin"))
        #expect(sb.exists("Downloads/old-keep.zip"))
    }

    @Test("dry-run 之后路径被换成指向外部的链接：apply 前重查，拒绝")
    func swappedToLinkRefused() throws {
        let sb = try Sandbox()
        let outside = try Sandbox()  // 另一个临时目录，当作「主目录以外」
        outside.file("precious.txt")
        sb.dir("Library/Caches/TestApp/sub")
        let e = sb.engine(rules: sb.rules)
        let p = try e.plan(ids: ["tc"])
        try FileManager.default.removeItem(atPath: sb.home + "/Library/Caches/TestApp/sub")
        try FileManager.default.createSymbolicLink(atPath: sb.home + "/Library/Caches/TestApp/sub", withDestinationPath: outside.home)
        let r = try e.apply(ids: ["tc"], token: p.token)
        #expect(r.skipped.count == 1 && r.skipped[0].contains("outside your home"))
        #expect(outside.exists("precious.txt"))
        #expect(sb.exists("Library/Caches/TestApp/sub"))
    }

    @Test("只读档、未知 id、空 id 整体拒绝，不发 token")
    func readonlyRejected() throws {
        let sb = try Sandbox()
        let e = sb.engine(rules: sb.rules)
        #expect(throws: RakeError.rejected(["tl"])) { try e.plan(ids: ["tl"]) }
        #expect(throws: RakeError.rejected(["nope"])) { try e.plan(ids: ["tc", "nope"]) }
        #expect(throws: RakeError.rejected(["(none)"])) { try e.plan(ids: [" ", ""]) }
        #expect(e.plans.isEmpty)
    }

    @Test("apply 写一行历史，存在 stateDir 下")
    func history() throws {
        let sb = try Sandbox()
        sb.file("Library/Caches/TestApp/a.bin")
        let e = sb.engine(rules: sb.rules)
        _ = try e.apply(ids: ["tc"], token: try e.plan(ids: ["tc"]).token)
        #expect(e.history().count == 1)
        #expect(sb.exists(".rake-state/history.json"))
    }
}

@Suite("KEEP 与守卫") struct GuardTests {
    @Test("KEEP 命中被拒：规则指到钥匙串、iCloud、照片图库也不删")
    func keepRefused() throws {
        let sb = try Sandbox()
        sb.file("Library/Keychains/login.keychain-db")
        sb.file("Library/Mobile Documents/com~apple~CloudDocs/a.txt")
        sb.file("Pictures/Photos Library.photoslibrary/database/x")
        sb.file("Library/Caches/TestApp/ok.bin")
        let greedy = Rule(id: "greedy", tier: .auto, kind: .caches) { c in
            [c.h("Library/Keychains/login.keychain-db"), c.h("Library/Mobile Documents/com~apple~CloudDocs"),
             c.h("Pictures/Photos Library.photoslibrary/database"), c.h("Library/Caches/TestApp/ok.bin")]
        }
        let e = sb.engine(rules: [greedy])
        let p = try e.plan(ids: ["greedy"])
        #expect(p.items[0].paths.map { $0.path } == ["~/Library/Caches/TestApp/ok.bin"])
        #expect(p.items[0].skipped.count == 3)
        #expect(p.items[0].skipped.allSatisfy { $0.contains("protected") })
        _ = try e.apply(ids: ["greedy"], token: p.token)
        #expect(sb.exists("Library/Keychains/login.keychain-db"))
        #expect(sb.exists("Library/Mobile Documents/com~apple~CloudDocs/a.txt"))
        #expect(sb.exists("Pictures/Photos Library.photoslibrary/database/x"))
        #expect(!sb.exists("Library/Caches/TestApp/ok.bin"))
    }

    @Test("结构性拒绝：/System、/usr、主目录本身、上层目录、一级目录、相对路径")
    func structural() throws {
        let sb = try Sandbox()
        let g = Guard(home: sb.home)
        sb.dir("Library/Caches"); sb.dir("Downloads")
        #expect(g.check("/System/Library") == .system)
        #expect(g.check("/usr/bin") == .system)
        #expect(g.check(sb.home) == .home)
        #expect(g.check((sb.home as NSString).deletingLastPathComponent) == .ancestor)
        #expect(g.check("/") == .system || g.check("/") == .ancestor)
        #expect(g.check(sb.home + "/Downloads") == .toplevel)
        #expect(g.check(sb.home + "/Library/Caches") == .keep("folders"))
        #expect(g.check("Library/Caches/x") == .relative)
        #expect(g.check(sb.home + "/Library/Caches/../Keychains") == .relative)
        #expect(g.check(sb.home + "/Library/Caches/missing") == .gone)
        #expect(g.check("/private/tmp") != nil)
    }

    @Test("链接：指向外部拒绝，指向主目录内放行；父目录是链接时按真实位置判")
    func links() throws {
        let sb = try Sandbox()
        let outside = try Sandbox()
        outside.file("data.txt")
        sb.file("Library/Caches/TestApp/inner.bin")
        let fm = FileManager.default
        try fm.createSymbolicLink(atPath: sb.home + "/Library/Caches/TestApp/out", withDestinationPath: outside.home)
        try fm.createSymbolicLink(atPath: sb.home + "/Library/Caches/TestApp/in", withDestinationPath: sb.home + "/Library/Caches/TestApp/inner.bin")
        try fm.createSymbolicLink(atPath: sb.home + "/Library/Caches/TestApp/dangling", withDestinationPath: "/nonexistent/x")
        try fm.createSymbolicLink(atPath: sb.home + "/Library/Caches/Via", withDestinationPath: outside.home)
        let g = Guard(home: sb.home)
        #expect(g.check(sb.home + "/Library/Caches/TestApp/out") == .link)
        #expect(g.check(sb.home + "/Library/Caches/TestApp/dangling") == .link)
        #expect(g.check(sb.home + "/Library/Caches/TestApp/in") == nil)
        #expect(g.check(sb.home + "/Library/Caches/Via/data.txt") == .outside)
    }

    @Test("真 FileManager.trashItem（默认关；RAKE_TEST_REAL_TRASH=1 才跑，只动自己放的一个临时文件）")
    func realTrash() throws {
        guard ProcessInfo.processInfo.environment["RAKE_TEST_REAL_TRASH"] == "1" else { return }
        let sb = try Sandbox()
        let name = "rake-test-\(UUID().uuidString).txt"
        sb.file("Downloads/" + name)
        var out: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: sb.home + "/Downloads/" + name), resultingItemURL: &out)
        #expect(!sb.exists("Downloads/" + name))
        let moved = try #require(out as URL?)
        #expect(FileManager.default.fileExists(atPath: moved.path))
        try FileManager.default.removeItem(at: moved)  // 只删自己刚放进去的这一个
    }
}
