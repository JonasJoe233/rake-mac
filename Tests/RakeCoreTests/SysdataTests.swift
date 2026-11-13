import Foundation
import Testing
@testable import RakeCore

@Suite("系统数据按差值算，「已用」等于整盘已用") struct SysdataTests {
    /// 扫描存下的快照是字节数，比界面上取整后的 GB 准
    func snapshot(_ sb: Sandbox) throws -> [String: Int64] {
        let dir = sb.home + "/.rake-state/snapshots"
        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: dir).first)
        return try JSONDecoder().decode([String: Int64].self, from: Data(contentsOf: URL(fileURLWithPath: dir + "/" + name)))
    }

    @Test("差值正常：系统数据 = 已用 − 其他各块，各块之和等于已用")
    func residual() throws {
        let sb = try Sandbox()
        sb.file("Documents/a.txt", String(repeating: "d", count: 50_000))
        sb.file(".npm/_cacache/x", String(repeating: "n", count: 40_000))
        let r = sb.engine().scan()
        let b = try snapshot(sb)
        let used: Int64 = (100 << 30) - (10 << 30)
        let others = b.filter { $0.key != "free" && $0.key != "sysdata" }.values.reduce(0, +)
        #expect(b["sysdata"] == used - others)
        #expect(b.filter { $0.key != "free" }.values.reduce(0, +) == used)
        #expect(r.used == gb(used))
        #expect(r.overcount == 0)
        #expect(r.stone("sysdata")?.kind == .system)
        #expect(r.stone("unk") == nil)
    }

    @Test("差值为负：系统数据取 0，超出的量记进 overcount")
    func negative() throws {
        let sb = try Sandbox()
        sb.file("Documents/big.bin", String(repeating: "b", count: 3_000_000))
        // 已用只有 1 MB，主目录里却量到 3 MB
        let v = VolumeInfo(total: 10_000_000, free: 9_000_000, dataUsed: 0, vmUsed: 0, swapUsed: 0, uptimeDays: 1)
        let r = sb.engine(volumes: v).scan()
        let b = try snapshot(sb)
        #expect(b["sysdata"] == 0)
        let others = b.filter { $0.key != "free" && $0.key != "sysdata" }.values.reduce(0, +)
        #expect(others > 1_000_000)
        #expect(r.overcount == gb(others - 1_000_000))
        #expect(r.overcount >= 0.002)
        #expect(r.used == gb(1_000_000))
        let json = String(decoding: try JSONEncoder().encode(r), as: UTF8.self)
        #expect(json.contains("\"used\"") && json.contains("\"overcount\""))
    }

    @Test("应用更新包跳过不到 1 MB 的项")
    func updFloor() throws {
        let sb = try Sandbox()
        sb.dir("Library/Caches/com.empty.app/org.sparkle-project.Sparkle")
        sb.age("Library/Caches/com.empty.app/org.sparkle-project.Sparkle", 1)
        sb.file("Library/Caches/com.big.app/org.sparkle-project.Sparkle/u.zip", String(repeating: "u", count: 2_000_000))
        sb.age("Library/Caches/com.big.app/org.sparkle-project.Sparkle", 1)
        let p = try sb.engine(rules: Rules.standard).plan(ids: ["upd"])
        let paths = p.items.first { $0.id == "upd" }?.paths.map { $0.path } ?? []
        #expect(paths == ["~/Library/Caches/com.big.app/org.sparkle-project.Sparkle"])
    }
}
