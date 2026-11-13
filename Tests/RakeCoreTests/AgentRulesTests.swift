import Foundation
import Testing
@testable import RakeCore

@Suite("manual 档：AI Agent 虚拟机、缓存、本地模型") struct AgentRulesTests {
    /// 假主目录里按真实布局造这几类目录，文件都很小
    func seeded() throws -> Sandbox {
        let sb = try Sandbox()
        let big = String(repeating: "v", count: 30000)
        sb.file("Library/Application Support/Claude/vm_bundles/claudevm.bundle/rootfs.img", big)
        sb.file("Library/Application Support/Claude-3p/vm_bundles/claudevm.bundle/sessiondata.img", big)
        sb.file("Library/Caches/Doubao/Default/Cache/data_0", big)
        sb.file("Library/Application Support/Doubao/gecko_cache/f27e/res.bin", big)
        sb.file(".cache/codex-runtimes/codex-primary-runtime/dependencies/node.tar", big)
        sb.file(".cache/huggingface/hub/models--test--tiny/blob", big)
        sb.file(".ollama/models/blobs/sha256-test", big)
        sb.file(".lmstudio/models/test/tiny.gguf", big)
        return sb
    }

    @Test("manual 规则只有这三条，档位都是 manual")
    func list() {
        #expect(Rules.manual.map { $0.id } == ["agentvm", "agentcache", "llm"])
        #expect(Rules.manual.allSatisfy { $0.tier == .manual && !$0.tier.pickable })
        #expect(Set(Rules.manual.map { $0.id }).isDisjoint(with: Rules.standard.map { $0.id }))
    }

    @Test("扫描识别为对应类别和 manual 档，大小算进去")
    func recognized() throws {
        let sb = try seeded()
        let r = sb.engine().scan()
        // 界面上的 size 按 GB 取三位，30 KB 的小文件显示 0。字节数看扫描存下的快照
        let snapDir = sb.home + "/.rake-state/snapshots"
        let snapName = try #require(try FileManager.default.contentsOfDirectory(atPath: snapDir).first)
        let bytes = try JSONDecoder().decode([String: Int64].self, from: Data(contentsOf: URL(fileURLWithPath: snapDir + "/" + snapName)))
        let want: [String: Kind] = ["agentvm": .tools, "agentcache": .caches, "llm": .tools]
        for (id, kind) in want {
            let s = try #require(r.stone(id))
            #expect(s.kind == kind)
            #expect(s.tier == .manual)
            #expect((bytes[id] ?? 0) >= 60000)  // 每类至少两个 30 KB 的文件
            #expect(s.why?.isEmpty == false && s.cmd?.isEmpty == false)
        }
        let ids = r.stones.map { $0.id }
        #expect(Set(ids).count == ids.count)
    }

    @Test("每条 manual 路径都过 Guard，不碰 KEEP")
    func guarded() throws {
        let sb = try seeded()
        let e = sb.engine()
        let ctx = e.context
        for r in Rules.manual {
            let found = r.find(ctx)
            #expect(!found.isEmpty)
            for p in found { #expect(e.guardian.check(p) == nil) }
        }
    }

    @Test("plan 拒绝 manual 档，不发 token，什么都不删")
    func noToken() throws {
        let sb = try seeded()
        let e = sb.engine()
        for id in ["agentvm", "agentcache", "llm"] {
            #expect(throws: RakeError.rejected([id])) { try e.plan(ids: [id]) }
        }
        sb.file(".npm/_cacache/x")
        #expect(throws: RakeError.rejected(["agentvm"])) { try e.plan(ids: ["npm", "agentvm"]) }  // 混进一个也整体拒绝
        for rel in ["Library/Application Support/Claude/vm_bundles/claudevm.bundle/rootfs.img",
                    "Library/Application Support/Claude-3p/vm_bundles/claudevm.bundle/sessiondata.img",
                    "Library/Caches/Doubao/Default/Cache/data_0", ".cache/codex-runtimes", ".cache/huggingface",
                    ".ollama/models", ".lmstudio/models", ".npm/_cacache/x"] {
            #expect(sb.exists(rel))
        }
    }

    @Test("manual 规则都有中英文案")
    func strings() throws {
        let all = try JSONDecoder().decode([String: [String: String]].self, from: Sandbox.strings.json)
        for lang in ["en", "zh-Hans"] {
            for r in Rules.manual { for f in ["label", "why", "cmd"] { #expect(all[lang]!["rule.\(r.id).\(f)"]?.isEmpty == false) } }
        }
    }
}
