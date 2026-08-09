// swift-tools-version:6.0
import PackageDescription

// swift-testing 要求 tools-version 6.0；各目标都显式钉在 Swift 5 语言模式，
// 好让加目标这件事不顺带改变应用的并发诊断。要升 Swift 6 语言模式是另一件事。
let swift5Mode: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Workdesk",
    // iOS 17 是 CKSyncEngine 的硬要求，见 ADR-0006。
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // iOS 的 Xcode 工程从包外引用核心与 iOS 界面，得有 library 产品可拿。
        .library(name: "WorkdeskCore", targets: ["WorkdeskCore"]),
        .library(name: "WorkdeskiOS", targets: ["WorkdeskiOS"]),
    ],
    targets: [
        // 平台中立的核心：模型、Store、TodayClock 与同步全套。两端 UI 共用这一份，
        // 「规矩一条不改」靠的就是两端跑同一份代码，见 ADR-0006。
        .target(
            name: "WorkdeskCore",
            path: "Sources/WorkdeskCore",
            swiftSettings: swift5Mode
        ),
        // iOS 界面。住在包里而不是 Xcode 工程里，好让加减 UI 文件不必手改 pbxproj；
        // 文件整个用 #if os(iOS) 圈住，在 macOS 上编成空模块，swift test 因此照跑。
        // Xcode 那边只剩一个 @main 薄壳（ios/），链接这个产品。
        .target(
            name: "WorkdeskiOS",
            dependencies: ["WorkdeskCore"],
            path: "Sources/WorkdeskiOS",
            swiftSettings: swift5Mode
        ),
        // macOS 界面与应用入口。
        .executableTarget(
            name: "Workdesk",
            dependencies: ["WorkdeskCore"],
            path: "Sources/Workdesk",
            swiftSettings: swift5Mode
        ),
        .testTarget(
            name: "WorkdeskTests",
            dependencies: ["WorkdeskCore"],
            path: "Tests/WorkdeskTests",
            swiftSettings: swift5Mode
        )
    ]
)
