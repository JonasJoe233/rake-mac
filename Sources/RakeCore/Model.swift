import Foundation

public enum Kind: String, Codable, CaseIterable {
    case free, content, tools, system, caches, unknown
}

/// auto 直接删；decide 移进废纸篓；later / manual 只读，不提供删除。
public enum Tier: String, Codable {
    case auto, decide, later, manual
    public var pickable: Bool { self == .auto || self == .decide }
}

public enum Method: String, Codable {
    case remove, trash
}

/// v7 界面用的一块卵石。size / grow 单位是 GiB。
public struct Stone: Codable, Equatable {
    public var id: String
    public var label: String
    public var size: Double
    public var kind: Kind
    public var tier: Tier?
    public var why: String?
    public var cmd: String?
    public var grow: Double?
}

public struct ScanResult: Codable {
    public var scannedAt: String
    public var growBase: String?
    public var stones: [Stone]
    public var keep: [[String]]
    public var log: [[String]]
    public var total: Double
    public var deniedCount: Int
    public var denied: [String]

    enum CodingKeys: String, CodingKey {
        case scannedAt = "scanned_at", growBase = "grow_base", stones, keep, log, total
        case deniedCount = "denied_count", denied
    }

    public func stone(_ id: String) -> Stone? { stones.first { $0.id == id } }

    /// grow_base 没有时写 null，不省略：界面按 null 显示「—」。
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scannedAt, forKey: .scannedAt)
        try c.encode(growBase, forKey: .growBase)
        try c.encode(stones, forKey: .stones)
        try c.encode(keep, forKey: .keep)
        try c.encode(log, forKey: .log)
        try c.encode(total, forKey: .total)
        try c.encode(deniedCount, forKey: .deniedCount)
        try c.encode(denied, forKey: .denied)
    }
}

/// 编码成 v7 要的 ["路径", GiB] 二元数组。
public struct PathEntry: Codable, Equatable {
    public var path: String
    public var size: Double
    public init(_ path: String, _ size: Double) { self.path = path; self.size = size }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(path)
        try c.encode(size)
    }
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        path = try c.decode(String.self)
        size = try c.decode(Double.self)
    }
}

public struct PlanItem: Codable {
    public var id: String
    public var label: String
    public var size: Double
    public var method: Method
    public var paths: [PathEntry]
    public var skipped: [String]
}

public struct Plan: Codable {
    public var token: String
    public var ids: [String]
    public var items: [PlanItem]
    public var expiresIn: Int

    enum CodingKeys: String, CodingKey { case token, ids, items, expiresIn = "expires_in" }
}

public struct ApplyResult: Codable {
    public var freed: Double      // 卷可用空间实际增加的 GiB
    public var removed: Double    // 直接删掉的 GiB（按 plan 时的大小）
    public var trashed: Double    // 移进废纸篓的 GiB，清倒废纸篓前不算腾出
    public var done: [String]
    public var skipped: [String]
    public var errors: [String]
}

public enum RakeError: Error, CustomStringConvertible, Equatable {
    case rejected([String])
    case tokenInvalid
    case tokenExpired
    case idsMismatch

    public var description: String {
        switch self {
        case .rejected(let ids): return "rejected: " + ids.joined(separator: ", ")
        case .tokenInvalid: return "plan token is invalid or already used"
        case .tokenExpired: return "plan token expired, build the list again"
        case .idsMismatch: return "ids differ from the reviewed list"
        }
    }
}

let GiB = 1024.0 * 1024 * 1024
let MiB: Int64 = 1024 * 1024

func gb(_ bytes: Int64) -> Double { (Double(max(bytes, 0)) / GiB * 100).rounded() / 100 }
