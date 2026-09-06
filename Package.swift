// swift-tools-version: 6.2
import PackageDescription

// 拆分为「稳定启动器 + 动态库」:辅助功能授权绑定在启动器可执行文件上,
// 它永不变化;日常改代码只重新编译 YiJianCore.dylib,授权不会失效(无需签名证书)。
let package = Package(
    name: "YiJian",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "YiJian", targets: ["YiJianLauncher"]),
        .library(name: "YiJianCore", type: .dynamic, targets: ["YiJianCore"]),
    ],
    targets: [
        .executableTarget(
            name: "YiJianLauncher",
            path: "Sources/YiJianLauncher",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "YiJianCore",
            path: "Sources/YiJian",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
