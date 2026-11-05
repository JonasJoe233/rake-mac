import Darwin
import Foundation

/// 删除前的最后一道检查。plan 和 apply 都调它，没有第二份。
/// 返回 nil 表示可以删；否则返回拒绝原因。
public struct Guard {
    public enum Refusal: Equatable {
        case relative, system, home, ancestor, outside, toplevel, link, gone
        case keep(String)   // KEEP 条目的 key
    }

    public struct Keep {
        public enum Mode { case subtree, exact, componentSuffix }
        public let key: String
        public let mode: Mode
        public let paths: [String]   // 相对主目录；componentSuffix 时是后缀
    }

    /// 通用 KEEP：每台 Mac 都该护住的位置。subtree = 里面什么都不删；exact = 文件夹本身和它的上层不删。
    public static let standardKeep: [Keep] = [
        Keep(key: "keychains", mode: .subtree, paths: ["Library/Keychains"]),
        Keep(key: "cloud", mode: .subtree, paths: ["Library/Mobile Documents", "Library/CloudStorage"]),
        Keep(key: "mail", mode: .subtree, paths: ["Library/Mail", "Library/Messages"]),
        Keep(key: "photos", mode: .componentSuffix, paths: [".photoslibrary"]),
        Keep(key: "backups", mode: .subtree, paths: ["Library/Application Support/MobileSync"]),
        Keep(key: "keys", mode: .subtree, paths: [".ssh", ".gnupg"]),
        Keep(key: "folders", mode: .exact, paths: [
            "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public", "Applications",
            ".Trash", "Library", "Library/Caches", "Library/Application Support", "Library/Containers",
            "Library/Group Containers", "Library/Preferences", ".cache", ".npm", ".local", ".config",
        ]),
    ]

    static let systemPrefixes = ["/System", "/usr", "/bin", "/sbin", "/Library", "/Applications", "/opt", "/private/etc"]

    public let home: String
    let keep: [(Keep, [String])]

    public init(home: String, keep: [Keep] = Guard.standardKeep) {
        let h = realPath(home) ?? home
        self.home = h
        self.keep = keep.map { k in (k, k.mode == .componentSuffix ? k.paths : k.paths.map { h + "/" + $0 }) }
    }

    static func under(_ p: String, _ root: String) -> Bool { p == root || p.hasPrefix(root + "/") }

    public func check(_ path: String) -> Refusal? {
        guard path.hasPrefix("/") else { return .relative }
        let parts = path.split(separator: "/")
        if parts.contains(where: { $0 == ".." || $0 == "." }) { return .relative }
        if parts.isEmpty { return .ancestor }  // "/" 本身
        guard let st = lstatInfo(path) else { return .gone }
        let lexical = "/" + parts.joined(separator: "/")
        let parent = (lexical as NSString).deletingLastPathComponent
        guard let parentReal = realPath(parent) else { return .gone }
        let name = (lexical as NSString).lastPathComponent
        let real = parentReal == "/" ? "/" + name : parentReal + "/" + name

        for p in [lexical, real] where Guard.systemPrefixes.contains(where: { Guard.under(p, $0) }) {
            return .system
        }
        if real == home || lexical == home { return .home }
        if real == "/" || home.hasPrefix(real + "/") { return .ancestor }
        guard real.hasPrefix(home + "/") else { return .outside }
        let depth = real.dropFirst(home.count + 1).split(separator: "/").count
        if depth < 2 { return .toplevel }

        if (st.st_mode & S_IFMT) == S_IFLNK {
            // 链接本身在主目录里也不行，目标必须也在主目录里
            let target = realPath(lexical) ?? linkTarget(lexical, parentReal)
            if !(target.hasPrefix(home + "/")) { return .link }
        }

        for (k, roots) in keep {
            switch k.mode {
            case .subtree:
                for r in roots where Guard.under(real, r) || r.hasPrefix(real + "/") { return .keep(k.key) }
            case .exact:
                for r in roots where real == r || r.hasPrefix(real + "/") { return .keep(k.key) }
            case .componentSuffix:
                let comps = real.split(separator: "/")
                for s in roots where comps.contains(where: { $0.hasSuffix(s) }) { return .keep(k.key) }
            }
        }
        return nil
    }

    func linkTarget(_ link: String, _ parentReal: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let n = readlink(link, &buf, Int(PATH_MAX))
        guard n > 0 else { return "/" }
        let t = String(cString: buf)
        let abs = t.hasPrefix("/") ? t : parentReal + "/" + t
        return (abs as NSString).standardizingPath
    }

    public func describe(_ r: Refusal, _ s: Strings) -> String {
        switch r {
        case .keep(let k): return s.t("guard.keep", ["name": s.t("keep." + k)])
        default: return s.t("guard.\(r)")
        }
    }

    /// 界面「不能动」sheet 用：[名称, 原因]。
    public static func keepList(_ s: Strings) -> [[String]] {
        (standardKeep.map { $0.key } + ["system", "links"]).map { [s.t("keep." + $0), s.t("keep.\($0).why")] }
    }
}
