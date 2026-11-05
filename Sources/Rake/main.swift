import AppKit
import RakeCore

// 无界面开关（验收和排查用）：
//   Rake --scan-json            扫描并打印 JSON
//   Rake --plan-json id1,id2    对这几个 id 做 dry-run 并打印（不删）
//   Rake --snapshot <目录>      打开窗口，扫描出图、打开 auto 档清单，各截一张图后退出。不会点确认
let args = CommandLine.arguments

func emitJSON<T: Encodable>(_ v: T) {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write((try? e.encode(v)) ?? Data())
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

if args.contains("--scan-json") || args.contains("--plan-json") {
    do {
        let engine = Engine(.live(strings: try Resources.strings()))
        if let i = args.firstIndex(of: "--plan-json") {
            emitJSON(try engine.plan(ids: (i + 1 < args.count ? args[i + 1] : "").split(separator: ",").map(String.init)))
        } else {
            emitJSON(engine.scan())
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("rake: \(error)\n".data(using: .utf8)!)
        exit(2)
    }
}

RakeApp.main()
