// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rake",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Rake", targets: ["Rake"]),
        .library(name: "RakeCore", targets: ["RakeCore"]),
    ],
    targets: [
        .target(name: "RakeCore"),
        .executableTarget(name: "Rake", dependencies: ["RakeCore"]),
        .testTarget(name: "RakeCoreTests", dependencies: ["RakeCore"]),
    ]
)
