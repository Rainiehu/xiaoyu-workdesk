// swift-tools-version:6.0
import PackageDescription

// swift-testing 要求 tools-version 6.0；两个目标都显式钉在 Swift 5 语言模式，
// 好让加测试目标这件事不顺带改变应用的并发诊断。要升 Swift 6 语言模式是另一件事。
let swift5Mode: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Workdesk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Workdesk",
            path: "Sources/Workdesk",
            swiftSettings: swift5Mode
        ),
        .testTarget(
            name: "WorkdeskTests",
            dependencies: ["Workdesk"],
            path: "Tests/WorkdeskTests",
            swiftSettings: swift5Mode
        )
    ]
)
