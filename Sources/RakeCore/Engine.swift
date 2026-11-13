import Foundation

public struct EngineConfig {
    public var home: String
    public var stateDir: String
    public var strings: Strings
    public var rules: [Rule] = Rules.standard + Rules.manual
    public var keep: [Guard.Keep] = Guard.standardKeep
    public var scanSystem = true
    public var volumes: () -> VolumeInfo = VolumeInfo.live
    public var now: () -> Date = { Date() }
    public var trasher: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    public var planTTL: TimeInterval = 600
    public var minStoneGB = 0.01             // 小于这个的块不画（GB）

    public init(home: String, stateDir: String, strings: Strings) {
        self.home = home; self.stateDir = stateDir; self.strings = strings
    }

    public static func live(strings: Strings) -> EngineConfig {
        let home = NSHomeDirectory()
        return EngineConfig(home: home, stateDir: home + "/Library/Application Support/Rake", strings: strings)
    }
}

/// 扫描、dry-run、删除。apply 只认 plan 发的 token，只动那份清单里的路径。
public final class Engine {
    public let config: EngineConfig
    public let guardian: Guard
    let lock = NSLock()
    var plans: [String: Stored] = [:]

    struct Entry { let id: String; let path: String; let method: Method; let bytes: Int64 }
    struct Stored { let ids: [String]; let expires: Date; let entries: [Entry]; let labels: [String: String] }

    public init(_ config: EngineConfig) {
        self.config = config
        guardian = Guard(home: config.home, keep: config.keep)
    }

    var s: Strings { config.strings }
    var home: String { config.home }
    func h(_ p: String) -> String { home + "/" + p }
    func disp(_ p: String) -> String {
        for r in [home, guardian.home] where p == r || p.hasPrefix(r + "/") { return "~" + p.dropFirst(r.count) }
        return p
    }
    func sizeOf(_ p: String) -> Int64 { lstatInfo(p) == nil ? 0 : Walker.size(p) }
    var context: RuleContext { RuleContext(home: home, now: config.now()) }

    func candidates(_ r: Rule, _ ctx: RuleContext) -> [String] {
        r.find(ctx).filter { r.minAge == 0 || ctx.age($0) > r.minAge }
    }

    static func normalize(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: plan

    public func plan(ids raw: [String]) throws -> Plan {
        let ids = Engine.normalize(raw)
        let rules = Dictionary(uniqueKeysWithValues: config.rules.map { ($0.id, $0) })
        let bad = ids.filter { rules[$0]?.tier.pickable != true }
        if ids.isEmpty || !bad.isEmpty { throw RakeError.rejected(bad.isEmpty ? ["(none)"] : bad) }
        let ctx = context
        var items: [PlanItem] = [], entries: [Entry] = [], labels: [String: String] = [:]
        for id in ids {
            let r = rules[id]!
            var item = PlanItem(id: id, label: s.t("rule.\(id).label"), size: 0, method: r.method, paths: [], skipped: [])
            labels[id] = item.label
            for p in candidates(r, ctx) {
                if let why = guardian.check(p) {
                    item.skipped.append(disp(p) + " (" + guardian.describe(why, s) + ")")
                    continue
                }
                let b = sizeOf(p)
                if b < r.minSize { continue }
                item.paths.append(PathEntry(disp(p), gb(b)))
                item.size += gb(b)
                entries.append(Entry(id: id, path: p, method: r.method, bytes: b))
            }
            item.size = (item.size * 1000).rounded() / 1000  // 和 gb() 同精度，不到 1 GB 时按 MB 显示
            items.append(item)
        }
        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<24).map { _ in UInt8.random(in: 0...255, using: &rng) }
        let token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let now = config.now()
        lock.lock()
        plans = plans.filter { $0.value.expires > now }
        plans[token] = Stored(ids: ids, expires: now.addingTimeInterval(config.planTTL), entries: entries, labels: labels)
        lock.unlock()
        return Plan(token: token, ids: ids, items: items, expiresIn: Int(config.planTTL))
    }

    // MARK: apply

    /// progress：每清完一个 id 回调一次（id、直接删掉的 GB、移进废纸篓的 GB、跳过几条），给界面逐项打勾。
    public func apply(ids raw: [String], token: String,
                      progress: ((String, Double, Double, Int) -> Void)? = nil) throws -> ApplyResult {
        lock.lock()
        let stored = plans.removeValue(forKey: token)  // 一次性：查一次就作废，成败都一样
        lock.unlock()
        guard let st = stored else { throw RakeError.tokenInvalid }
        guard config.now() < st.expires else { throw RakeError.tokenExpired }
        guard st.ids == Engine.normalize(raw) else { throw RakeError.idsMismatch }
        let before = config.volumes().free
        var failed = Set<String>(), skipped: [String] = [], errors: [String] = []
        var removed: Int64 = 0, trashed: Int64 = 0
        for id in st.ids {
            var r: Int64 = 0, t: Int64 = 0, k = 0
            for e in st.entries where e.id == id {
                if let why = guardian.check(e.path) {  // 确认之后路径变成链接、被换走、已不在：都跳过
                    skipped.append(disp(e.path) + " (" + guardian.describe(why, s) + ")")
                    k += 1
                    continue
                }
                do {
                    switch e.method {
                    case .remove: try FileManager.default.removeItem(atPath: e.path); r += e.bytes
                    case .trash: try config.trasher(URL(fileURLWithPath: e.path)); t += e.bytes
                    }
                } catch {
                    errors.append(disp(e.path) + ": " + error.localizedDescription)
                    failed.insert(e.id)
                }
            }
            removed += r; trashed += t
            progress?(id, gb(r), gb(t), k)
        }
        let after = config.volumes().free
        let done = st.ids.filter { !failed.contains($0) }
        let sep = s.lang.hasPrefix("zh") ? "、" : ", "
        appendHistory([dayString(), done.compactMap { st.labels[$0] }.joined(separator: sep),
                       fmtSize(gb(removed)), trashed > 0 ? s.t("rule.trash.label") + " +" + fmtSize(gb(trashed)) : "—"])
        return ApplyResult(freed: gb(after - before), removed: gb(removed), trashed: gb(trashed),
                           done: done, skipped: skipped, errors: errors)
    }

    // MARK: state

    func dayString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: config.now())
    }

    var historyURL: URL { URL(fileURLWithPath: config.stateDir + "/history.json") }

    func history() -> [[String]] {
        guard let d = try? Data(contentsOf: historyURL), let rows = try? JSONDecoder().decode([[String]].self, from: d) else { return [] }
        return rows
    }

    func appendHistory(_ row: [String]) {
        try? FileManager.default.createDirectory(atPath: config.stateDir, withIntermediateDirectories: true)
        let rows = [row] + history()
        try? JSONEncoder().encode(Array(rows.prefix(200))).write(to: historyURL, options: .atomic)
    }

    func baseline() -> (String?, [String: Int64]) {
        let dir = config.stateDir + "/snapshots"
        let today = dayString()
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasSuffix(".json") && String($0.dropLast(5)) < today }.sorted()
        guard let last = names.last, let d = FileManager.default.contents(atPath: dir + "/" + last),
              let m = try? JSONDecoder().decode([String: Int64].self, from: d) else { return (nil, [:]) }
        return (String(last.dropLast(5)), m)
    }

    func saveSnapshot(_ bytes: [String: Int64]) {
        let dir = config.stateDir + "/snapshots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(bytes).write(to: URL(fileURLWithPath: dir + "/" + dayString() + ".json"), options: .atomic)
    }
}
