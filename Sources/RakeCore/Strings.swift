import Foundation

/// 读 i18n/strings.json。App、引擎、官网共用这一份字典。
public struct Strings {
    public let lang: String
    public let json: Data
    let table: [String: String]
    let fallback: [String: String]

    public init(json: Data, lang: String) throws {
        let all = try JSONDecoder().decode([String: [String: String]].self, from: json)
        self.json = json
        self.lang = all[lang] != nil ? lang : "en"
        table = all[self.lang] ?? [:]
        fallback = all["en"] ?? [:]
    }

    public static func load(_ url: URL, lang: String = Strings.language()) throws -> Strings {
        try Strings(json: Data(contentsOf: url), lang: lang)
    }

    /// 系统首选语言是中文就用简体中文，其余一律英文。RAKE_LANG 可覆盖。
    public static func language(_ preferred: [String] = Locale.preferredLanguages) -> String {
        if let o = ProcessInfo.processInfo.environment["RAKE_LANG"], !o.isEmpty { return o }
        return (preferred.first ?? "en").hasPrefix("zh") ? "zh-Hans" : "en"
    }

    public func t(_ key: String, _ vars: [String: String] = [:]) -> String {
        var s = table[key] ?? fallback[key] ?? key
        for (k, v) in vars { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }
}

/// 和界面里的 G() 一致（web/app.html）：参数是 GB。不到 1 GB 显示整数 MB，10 GB 以下留一位小数，再大取整。
func fmtSize(_ g: Double) -> String {
    if g <= 0 { return "0 MB" }
    let mb = Int((g * 1000).rounded())
    if mb < 1000 { return "\(max(1, mb)) MB" }
    return g >= 10 ? String(format: "%.0f GB", g) : String(format: "%.1f GB", g)
}
