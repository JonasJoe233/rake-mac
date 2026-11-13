import Foundation
import Testing
@testable import RakeCore

@Suite("单位：1000 进制，GB / MB") struct UnitsTests {
    func show(_ bytes: Int64) -> String { fmtSize(gb(bytes)) }

    @Test("999 MB、1 GB、15.7 GiB 的显示值")
    func samples() {
        #expect(show(999_000_000) == "999 MB")
        #expect(show(1_000_000_000) == "1.0 GB")
        #expect(show(Int64(15.7 * 1_073_741_824)) == "17 GB")   // 15.7 GiB = 16.86 GB
        #expect(gb(Int64(15.7 * 1_073_741_824)) == 16.858)
    }

    @Test("边界：0、不到 1 MB、9.94 GB、10 GB")
    func edges() {
        #expect(show(0) == "0 MB")
        #expect(show(400_000) == "0 MB")         // gb() 只留到 1 MB，不到 0.5 MB 记为 0
        #expect(show(600_000) == "1 MB")
        #expect(show(999_600_000) == "1.0 GB")   // 四舍五入到 1000 MB 时进位成 GB
        #expect(show(9_940_000_000) == "9.9 GB")
        #expect(show(10_000_000_000) == "10 GB")
    }

    @Test("清单里每项的合计和路径行同精度：43 MB 不会显示成 40 MB")
    func planItemPrecision() throws {
        let sb = try Sandbox()
        sb.file("Library/Caches/TestApp/a", String(repeating: "x", count: 21_600_000))
        sb.file("Library/Caches/TestApp/b", String(repeating: "y", count: 21_600_000))
        let p = try sb.engine(rules: sb.rules).plan(ids: ["tc"])
        let item = try #require(p.items.first)
        #expect(item.size == item.paths.reduce(0) { $0 + $1.size })
        #expect(item.size >= 0.043)   // 两位小数时会被截成 0.04，显示「40 MB」
    }
}
