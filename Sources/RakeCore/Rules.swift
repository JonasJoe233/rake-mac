import Foundation

/// 一条清理规则。只收每台 Mac 都可能有的通用位置。
/// auto：可再生缓存，直接删。decide：要你看一眼，移进废纸篓。later / manual：只读，规则里没有可删路径。
public struct Rule {
    public let id: String
    public let tier: Tier
    public let kind: Kind
    public var minAge: TimeInterval = 0       // 改动时间至少这么久以前
    public var minSize: Int64 = 0             // 单项至少这么大（要量过才知道）
    public let find: (RuleContext) -> [String]

    public var method: Method { tier == .decide ? .trash : .remove }
}

public struct RuleContext {
    public let home: String
    public let now: Date
    public func h(_ p: String) -> String { home + "/" + p }
    public func g(_ pats: String...) -> [String] { pats.flatMap { glob(h($0)) } }
    public func exists(_ p: String) -> [String] { lstatInfo(h(p)) != nil ? [h(p)] : [] }
    public func age(_ p: String) -> TimeInterval {
        guard let st = lstatInfo(p) else { return 0 }
        return now.timeIntervalSince1970 - Double(st.st_mtimespec.tv_sec)
    }
}

public enum Rules {
    static let hour: TimeInterval = 3600
    static let day: TimeInterval = 86400

    public static let standard: [Rule] = [
        Rule(id: "upd", tier: .auto, kind: .caches, minAge: 6 * hour, minSize: MB) { c in  // 不到 1 MB 的多是空的 Sparkle 目录，不列
            c.g("Library/Caches/*-updater/update.zip", "Library/Caches/*-updater/pending",
                "Library/Caches/*.ShipIt/update.*", "Library/Caches/*/org.sparkle-project.Sparkle",
                "Library/Containers/*/Data/Library/Caches/*/org.sparkle-project.Sparkle")
        },
        Rule(id: "crx", tier: .auto, kind: .caches, minAge: 6 * hour) { c in
            c.g("Library/Application Support/Google/GoogleUpdater/crx_cache/*")
        },
        Rule(id: "vsix", tier: .auto, kind: .caches, minAge: 6 * hour) { c in
            c.exists("Library/Application Support/Code/CachedExtensionVSIXs")
        },
        Rule(id: "ext", tier: .auto, kind: .caches) { c in orphanExtensions(c) },
        Rule(id: "npm", tier: .auto, kind: .caches) { c in c.exists(".npm/_cacache") },
        Rule(id: "pip", tier: .auto, kind: .caches) { c in c.exists("Library/Caches/pip") },
        Rule(id: "uv", tier: .auto, kind: .caches) { c in c.exists(".cache/uv") },
        Rule(id: "brew", tier: .auto, kind: .caches) { c in c.g("Library/Caches/Homebrew/*") },
        Rule(id: "dl", tier: .decide, kind: .content, minAge: 30 * day, minSize: 150 * MB) { c in
            let d = c.h("Downloads")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []
            return names.filter { !$0.hasPrefix(".") }.sorted().map { d + "/" + $0 }
        },
    ]

    /// manual 档：只认出来、量大小、写说明，不发删除 token。删了会不会丢东西还没查清的放这里。
    public static let manual: [Rule] = [
        // 桌面 AI Agent 在本机建的虚拟机。bundle 里除了系统镜像还有一块会话数据盘，删了丢什么还没查清
        Rule(id: "agentvm", tier: .manual, kind: .tools) { c in
            c.exists("Library/Application Support/Claude/vm_bundles") + c.exists("Library/Application Support/Claude-3p/vm_bundles")
        },
        // 桌面 AI 应用的下载缓存和运行时
        Rule(id: "agentcache", tier: .manual, kind: .caches) { c in
            c.exists("Library/Caches/Doubao") + c.exists("Library/Application Support/Doubao/gecko_cache")
                + c.exists(".cache/codex-runtimes")
        },
        // 本地模型。Ollama、LM Studio 只认 models 子目录：主目录一级的点目录过不了 Guard
        Rule(id: "llm", tier: .manual, kind: .tools) { c in
            c.exists(".cache/huggingface") + c.exists(".ollama/models") + c.exists(".lmstudio/models")
                + c.exists(".cache/lm-studio/models")
        },
    ]

    /// 编辑器扩展目录里，已被新版本替代、extensions.json 不再引用的旧版本。手装的孤儿不动。
    static func orphanExtensions(_ c: RuleContext) -> [String] {
        var out: [String] = []
        for d in [c.h(".vscode/extensions"), c.h(".cursor/extensions")] {
            guard let data = FileManager.default.contents(atPath: d + "/extensions.json"),
                  let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            let live = Set(entries.compactMap { $0["relativeLocation"] as? String })
            let ids = Set(entries.compactMap { (($0["identifier"] as? [String: Any])?["id"] as? String)?.lowercased() })
            for name in ((try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []).sorted() {
                if live.contains(name) || name.hasPrefix(".") || name == "extensions.json" { continue }
                guard let r = name.range(of: #"^(.+?)-\d"#, options: .regularExpression) else { continue }
                let base = String(name[r]).dropLast(2)
                if ids.contains(base.lowercased()) { out.append(d + "/" + name) }
            }
        }
        return out
    }
}
