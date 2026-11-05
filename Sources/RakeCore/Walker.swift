import Darwin
import Foundation

/// 用 fts 量实占（st_blocks），和 du 同口径：稀疏文件按实占算，硬链接只算一次，不跨卷。
/// 读不到的目录跳过并计数，不要求完全磁盘访问权限。
struct Walk {
    var sizes: [String: Int64] = [:]   // 记录下来的路径 → 字节
    var total: Int64 = 0
    var denied = 0
    var deniedSamples: [String] = []

    mutating func merge(_ o: Walk) {
        sizes.merge(o.sizes) { a, _ in a }
        total += o.total
        denied += o.denied
        deniedSamples += o.deniedSamples.prefix(max(0, 20 - deniedSamples.count))
    }
}

enum Walker {
    /// 量 root。level ≤ recordDepth 的路径和 interesting 里的路径都会记下大小。
    static func walk(_ root: String, recordDepth: Int, interesting: Set<String> = []) -> Walk {
        var w = Walk()
        guard let cpath = strdup(root) else { return w }
        defer { free(cpath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { w.denied += 1; return w }
        defer { fts_close(fts) }
        var stack: [(level: Int, bytes: Int64)] = []  // 带层级：读不到的目录会先给 FTS_D、再给 FTS_DNR，不给 FTS_DP
        var seen = Set<UInt64>()  // 硬链接 (dev, ino)

        func blocks(_ e: UnsafeMutablePointer<FTSENT>) -> Int64 {
            guard let st = e.pointee.fts_statp?.pointee else { return 0 }
            if (st.st_mode & S_IFMT) != S_IFDIR && st.st_nlink > 1 {
                let key = (UInt64(UInt32(bitPattern: st.st_dev)) << 40) ^ st.st_ino
                if !seen.insert(key).inserted { return 0 }
            }
            return Int64(st.st_blocks) * 512
        }
        func add(_ b: Int64) {
            if stack.isEmpty { w.total += b } else { stack[stack.count - 1].bytes += b }
        }
        func record(_ e: UnsafeMutablePointer<FTSENT>, _ b: Int64) {
            let level = Int(e.pointee.fts_level)
            let path = String(cString: e.pointee.fts_path)
            if level <= recordDepth || interesting.contains(path) { w.sizes[path] = b }
        }

        while let e = fts_read(fts) {
            switch Int32(e.pointee.fts_info) {
            case FTS_D:
                stack.append((Int(e.pointee.fts_level), blocks(e)))
            case FTS_DP:
                let b = stack.popLast()?.bytes ?? 0
                record(e, b)
                add(b)
            case FTS_DNR, FTS_ERR, FTS_NS:
                w.denied += 1
                if w.deniedSamples.count < 20 { w.deniedSamples.append(String(cString: e.pointee.fts_path)) }
                var b: Int64 = 0
                if let top = stack.last, top.level == Int(e.pointee.fts_level), Int32(e.pointee.fts_info) == FTS_DNR {
                    b = stack.removeLast().bytes  // 已经 push 过的目录：在这里收尾
                } else if Int32(e.pointee.fts_info) == FTS_DNR {
                    b = blocks(e)
                }
                record(e, b)
                add(b)
            case FTS_DC, FTS_DOT:
                continue
            default:  // 文件、链接、其他
                let b = blocks(e)
                if Int(e.pointee.fts_level) <= recordDepth || !interesting.isEmpty { record(e, b) }
                add(b)
            }
        }
        return w
    }

    /// 并行量多个根。每个根各开一个 fts，按传入顺序分配给线程，大的放前面。
    static func walkAll(_ jobs: [(root: String, depth: Int)], interesting: Set<String>) -> [String: Walk] {
        var out = [Walk](repeating: Walk(), count: jobs.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
            let r = walk(jobs[i].root, recordDepth: jobs[i].depth, interesting: interesting)
            lock.lock(); out[i] = r; lock.unlock()
        }
        var m: [String: Walk] = [:]
        for (i, j) in jobs.enumerated() { m[j.root] = out[i] }
        return m
    }

    static func size(_ path: String) -> Int64 { walk(path, recordDepth: -1).total }
}
