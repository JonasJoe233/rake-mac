import Darwin
import Foundation

public struct VolumeInfo {
    public var total: Int64      // Data 卷所在容器总量
    public var free: Int64       // 可用
    public var dataUsed: Int64   // Data 卷已用
    public var vmUsed: Int64     // VM 卷已用（swap 文件）
    public var swapUsed: Int64
    public var uptimeDays: Double

    public init(total: Int64, free: Int64, dataUsed: Int64, vmUsed: Int64, swapUsed: Int64, uptimeDays: Double) {
        self.total = total; self.free = free; self.dataUsed = dataUsed
        self.vmUsed = vmUsed; self.swapUsed = swapUsed; self.uptimeDays = uptimeDays
    }

    /// APFS 各卷共享一个容器，statfs 给的已用是整个容器的，单卷已用要看 df。
    public static func live() -> VolumeInfo {
        let out = run("/bin/df", ["-k", "/System/Volumes/Data", "/System/Volumes/VM"])
        let rows = out.split(separator: "\n").dropFirst().map { $0.split(separator: " ", omittingEmptySubsequences: true) }
        func col(_ r: Int, _ c: Int) -> Int64 { rows.count > r && rows[r].count > c ? (Int64(rows[r][c]) ?? 0) * 1024 : 0 }
        var info = VolumeInfo(total: col(0, 1), free: col(0, 3), dataUsed: col(0, 2), vmUsed: col(1, 2),
                              swapUsed: 0, uptimeDays: 0)
        if info.total == 0 {  // 拿不到 df（不该发生）时退回容器级数据
            var s = statfs()
            if statfs(NSHomeDirectory(), &s) == 0 {
                let b = Int64(s.f_bsize)
                info.total = Int64(s.f_blocks) * b
                info.free = Int64(s.f_bavail) * b
                info.dataUsed = Int64(s.f_blocks - s.f_bfree) * b
            }
        }
        var xsw = xsw_usage()
        var n = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &xsw, &n, nil, 0) == 0 { info.swapUsed = Int64(xsw.xsu_used) }
        var tv = timeval()
        n = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &tv, &n, nil, 0) == 0 {
            info.uptimeDays = (Date().timeIntervalSince1970 - Double(tv.tv_sec)) / 86400
        }
        return info
    }
}

func run(_ exe: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

/// Darwin glob()。返回绝对路径，按字典序。
func glob(_ pattern: String) -> [String] {
    var g = glob_t()
    defer { globfree(&g) }
    guard Darwin.glob(pattern, 0, nil, &g) == 0 else { return [] }
    var out: [String] = []
    for i in 0..<Int(g.gl_pathc) {
        if let p = g.gl_pathv[i] { out.append(String(cString: p)) }
    }
    return out.sorted()
}

func lstatInfo(_ path: String) -> stat? {
    var st = stat()
    return lstat(path, &st) == 0 ? st : nil
}

func realPath(_ path: String) -> String? {
    guard let r = Darwin.realpath(path, nil) else { return nil }
    defer { free(r) }
    return String(cString: r)
}
