# Rake：项目规则（给 Agent 读）

Rake 是免费开源的 Mac 磁盘清理 App。先用一张卵石图告诉你空间去哪了，再给出删除前的 dry-run 清单，你确认后才删。仓库名 `rake-mac`，App 显示名 Rake。

## 红线（碰到就停下问维护者）

- 不 `git push`，不建远程仓库，不开 GitHub Pages，不发 Release。M5 之前只在本地 commit。
- 不装 Xcode，不装全局依赖（`brew install`、`npm -g`、`pip install` 都算）。只用 Command Line Tools 自带的 Swift 和系统命令。
- 不在维护者的真实文件上执行删除。真删只在 `FileManager.temporaryDirectory` 或 `mktemp -d` 造的目录里做。
- 代码和文案里不出现界面参考站点的名字，来源只写在 `NOTICE`。

## 目录结构

```
rake-mac/
├── CLAUDE.md                 # 本文件
├── LICENSE / NOTICE          # MIT；视觉参考与第三方声明
├── VERSION                   # 版本号，build.sh、官网元信息都读它
├── Package.swift             # SwiftPM：RakeCore（库）+ Rake（App）+ RakeCoreTests
├── Sources/RakeCore/         # 引擎：扫描、规则、守卫（KEEP）、plan / apply
├── Sources/Rake/             # App 壳：SwiftUI 窗口 + WKWebView + JS bridge
├── Tests/RakeCoreTests/      # swift-testing 测试，真删只在临时目录
├── web/                      # App 里的界面：app.html、pebbles.js（卵石几何，官网共用）
├── i18n/strings.json         # 唯一文案字典（en / zh-Hans），引擎、App、官网共用
├── packaging/                # Info.plist、图标源
├── scripts/                  # build.sh、dmg.sh、test.sh、sync-site.sh、swiftpm-env.sh
├── install.sh                # curl 安装脚本
├── site/                     # 官网，纯静态单页；strings.json、pebbles.js 是同步来的副本
├── .github/workflows/        # release.yml（打 tag 出 dmg）、pages.yml（部署 site/）
└── build/                    # 产物（Rake.app、Rake.dmg），不进 git
```

## 命名

- Swift 类型 UpperCamel，文件名和主类型同名。规则 id 用短小写英文（`upd`、`npm`、`dl`），一旦发布不改。
- 文案 key 用点分：`app.*` 只给 App，`site.*` 只给官网，`rule.<id>.label|why|cmd`、`kind.*`、`tier.*` 两边共用。
- 新增文案必须同时写 `en` 和 `zh-Hans`，测试会查两边 key 一致。
- 改了 `i18n/strings.json` 或 `web/pebbles.js`，跑 `scripts/sync-site.sh` 同步到 `site/`。

## 规则怎么加

- 规则在 `Sources/RakeCore/Rules.swift`。只收每台 Mac 都可能有的通用缓存，不收只对某台机器有效的路径。
- 三档：`auto` 直接删；`decide` 移进废纸篓；`later` / `manual` 只读，不提供删除。
- 每条规则的路径都要过 `Guard.check()`。不要另写删除函数。

## 测试怎么跑

```
scripts/test.sh          # swift test（swift-testing）+ 文案 key 校验 + site 副本一致性
scripts/build.sh         # 编 arm64 和 x86_64，lipo 成 universal，组装并 ad-hoc 签名 build/Rake.app
scripts/dmg.sh           # 用 hdiutil 打 build/Rake.dmg
```

- 本机只有 Command Line Tools。`scripts/swiftpm-env.sh` 会自动绕开 CLT 26.2 的两处坑：旧的 `module.modulemap` 和 `SwiftBridging` 重名、`PackageDescription` 的 private interface 过期。装了 Xcode 的机器（含 CI）不触发。
- `swift build --arch arm64 --arch x86_64` 要 xcbuild，CLT 没有。所以分两次编再 `lipo`。
- 测试里的真删只在临时目录。默认用假废纸篓；设 `RAKE_TEST_REAL_TRASH=1` 才测真的 `FileManager.trashItem`，测完只删它自己放进去的那个文件。
- App 自带两个无界面开关，方便验收：`Rake --scan-json` 打印扫描结果；`Rake --snapshot <目录>` 扫描、出图、打开 auto 档的 dry-run 清单，各截一张图后退出，不会点确认删除。
