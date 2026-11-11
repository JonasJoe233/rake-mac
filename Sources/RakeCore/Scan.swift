import Foundation

/// 扫描：把整块盘切成互不重叠的块，每块一个稳定 id。只量每台 Mac 都有的位置。
extension Engine {
    struct Leaf { var stone: Stone; var bytes: Int64; var claims: [(String, Int64)] }

    static let systemRoots = ["/Applications", "/Library", "/opt/homebrew", "/usr/local", "/private/var", "/Users/Shared"]
    static let installData = "/System/Volumes/Data/macOS Install Data"
    // 大目录排前面，并行时不会最后才开始
    static let heavyLibrary = ["Application Support", "Containers", "Caches", "Group Containers", "Developer", "Mail", "Messages"]

    public func scan() -> ScanResult {
        let ctx = context
        let fm = FileManager.default
        var found: [String: [String]] = [:]
        for r in config.rules { found[r.id] = candidates(r, ctx) }
        let chat = ctx.g("Library/Messages", "Library/Containers/com.tencent.xinWeChat",
                         "Library/Group Containers/*.com.tencent.xinWeChat", "Library/Application Support/Telegram Desktop",
                         "Library/Group Containers/*.ru.keepcoder.Telegram", "Library/Application Support/Slack",
                         "Library/Containers/com.tinyspeck.slackmacgap", "Library/Application Support/discord",
                         "Library/Application Support/LarkShell", "Library/Containers/com.bytedance.macos.feishu",
                         "Library/Group Containers/*.feishu")
        let trashDir = h(".Trash")
        let interesting = Set(found.values.joined()).union(chat).union([trashDir])

        // 1. 量：主目录一级、~/Library 一级分别开 fts 并行；系统目录只要总量
        let top = ((try? fm.contentsOfDirectory(atPath: home)) ?? []).sorted().map { h($0) }
        let lib = h("Library")
        let libKids = ((try? fm.contentsOfDirectory(atPath: lib)) ?? []).sorted {
            (Engine.heavyLibrary.firstIndex(of: $0) ?? 99, $0) < (Engine.heavyLibrary.firstIndex(of: $1) ?? 99, $1)
        }.map { lib + "/" + $0 }
        var jobs = libKids.map { (root: $0, depth: 1) } + top.filter { $0 != lib }.map { (root: $0, depth: 2) }
        let sysRoots = config.scanSystem ? (Engine.systemRoots + [Engine.installData]).filter { lstatInfo($0) != nil } : []
        jobs += sysRoots.map { (root: $0, depth: 0) }
        let walks = Walker.walkAll(jobs, interesting: interesting)
        var sizes: [String: Int64] = [:]
        var denied = 0, deniedSamples: [String] = []
        for (root, w) in walks {
            sizes.merge(w.sizes) { a, _ in a }
            sizes[root] = w.total
            if !sysRoots.contains(root) {
                denied += w.denied
                deniedSamples += w.deniedSamples.prefix(max(0, 20 - deniedSamples.count))
            }
        }
        let libOwn = Int64(lstatInfo(lib)?.st_blocks ?? 0) * 512
        sizes[lib] = libKids.reduce(libOwn) { $0 + (walks[$1]?.total ?? 0) }
        func size(_ p: String) -> Int64 { sizes[p] ?? sizeOf(p) }

        // 2. 认领：规则和已知目录各自认领路径，再从所在的大块里扣掉
        var leaf: [Leaf] = []
        func add(_ id: String, _ kind: Kind, _ claims: [(String, Int64)], tier: Tier? = nil, why: String? = nil,
                 cmd: String? = nil, label: String? = nil, bytes: Int64? = nil) {
            let st = Stone(id: id, label: label ?? s.t("stone." + id), size: 0, kind: kind, tier: tier, why: why, cmd: cmd)
            leaf.append(Leaf(stone: st, bytes: bytes ?? claims.reduce(0) { $0 + $1.1 }, claims: claims))
        }
        for r in config.rules {
            let cl = (found[r.id] ?? []).filter { guardian.check($0) == nil }.map { ($0, size($0)) }.filter { $0.1 >= r.minSize }
            add(r.id, r.kind, cl, tier: r.tier, why: s.t("rule.\(r.id).why"),
                cmd: s.t("rule.\(r.id).cmd", ["n": "\(cl.count)"]), label: s.t("rule.\(r.id).label"))
        }
        if lstatInfo(trashDir) != nil {
            add("trash", .content, [(trashDir, size(trashDir))], tier: .manual, why: s.t("rule.trash.why"),
                cmd: s.t("rule.trash.cmd"), label: s.t("rule.trash.label"))
        }
        add("chat", .content, chat.map { ($0, size($0)) }, why: s.t("why.chat"))
        let v = config.volumes()
        if config.scanSystem {
            add("apps", .tools, [], why: s.t("why.apps"), bytes: (sizes["/Applications"] ?? 0) + size(h("Applications")))
            add("devenv", .tools, [], why: s.t("why.devenv"), bytes: (sizes["/opt/homebrew"] ?? 0) + (sizes["/usr/local"] ?? 0))
            add("sysdata", .system, [], why: s.t("why.sysdata"),
                bytes: ["/Library", "/private/var", "/Users/Shared"].reduce(0) { $0 + (sizes[$1] ?? 0) })
            if let mid = sizes[Engine.installData], mid > 500 * MiB {
                add("mid", .system, [], tier: .manual, why: s.t("rule.mid.why"), cmd: s.t("rule.mid.cmd"),
                    label: s.t("rule.mid.label"), bytes: mid)
            }
        } else {
            add("apps", .tools, [], why: s.t("why.apps"), bytes: size(h("Applications")))
        }

        // 3. 余量：大块减去被认领的部分。嵌套的认领只扣外层
        let all = leaf.flatMap { $0.claims }
        let claims = all.filter { c in !all.contains { o in c.0.hasPrefix(o.0 + "/") } }
        func under(_ p: String, _ rs: [String]) -> Bool { rs.contains { p == $0 || p.hasPrefix($0 + "/") } }
        func residual(_ roots: [String], _ excl: [String] = []) -> Int64 {
            roots.reduce(0) { $0 + size($1) } - excl.reduce(0) { $0 + size($1) }
                - claims.filter { under($0.0, roots) && !under($0.0, excl) }.reduce(0) { $0 + $1.1 }
        }
        let named = Set(["Library", "Applications", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music"].map { h($0) })
        let hidden = top.filter { ($0 as NSString).lastPathComponent.hasPrefix(".") }
        let photo = [h("Pictures"), h("Movies"), h("Music")]
        add("photo", .content, [], why: s.t("why.photo"), bytes: max(0, residual(photo)))
        add("docs", .content, [], why: s.t("why.docs"), bytes: max(0, residual([h("Documents"), h("Desktop"), h("Downloads")])))
        add("code", .content, [], why: s.t("why.code"),
            bytes: max(0, residual(top.filter { !hidden.contains($0) && !named.contains($0) })))
        add("dot", .tools, [], why: s.t("why.dot"), bytes: max(0, residual(hidden)))
        add("appdata", .tools, [], why: s.t("why.appdata"), bytes: max(0, residual([lib], [h("Library/Caches")])))
        add("appc", .caches, [], why: s.t("why.appc"), bytes: max(0, residual([h("Library/Caches")])))
        let classified = leaf.reduce(0) { $0 + $1.bytes }
        add("unk", .unknown, [], why: s.t("why.unk"), bytes: max(0, v.dataUsed - classified))
        add("sys", .system, [], why: s.t("why.sys"), bytes: max(0, v.total - v.free - v.dataUsed - v.vmUsed))
        add("swap", .system, [], tier: .manual,
            why: s.t("rule.swap.why", ["used": fmtSize(gb(v.swapUsed)), "days": String(format: "%.0f", v.uptimeDays)]),
            cmd: s.t("rule.swap.cmd"), label: s.t("rule.swap.label"), bytes: v.vmUsed)

        // 4. 增长、排序、存快照
        let (baseDate, base) = baseline()
        let order: [Kind] = [.free, .content, .tools, .system, .caches, .unknown]
        var stones = [Stone(id: "free", label: s.t("stone.free"), size: gb(v.free), kind: .free)]
        var snap: [String: Int64] = ["free": v.free]
        for l in leaf.sorted(by: { (order.firstIndex(of: $0.stone.kind)!, -$0.bytes) < (order.firstIndex(of: $1.stone.kind)!, -$1.bytes) }) {
            var st = l.stone
            st.size = gb(l.bytes)
            snap[st.id] = l.bytes
            if let prev = base[st.id], l.bytes - prev > Int64(GiB / 20) { st.grow = gb(l.bytes - prev) }
            if st.size >= config.minStoneGiB { stones.append(st) }
        }
        saveSnapshot(snap)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return ScanResult(scannedAt: f.string(from: config.now()), growBase: baseDate, stones: stones,
                          keep: Guard.keepList(s), log: history(), total: gb(v.total),
                          deniedCount: denied, denied: deniedSamples.map { disp($0) })
    }
}
