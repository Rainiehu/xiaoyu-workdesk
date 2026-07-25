// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Workdesk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Workdesk",
            path: "Sources/Workdesk"
        )
    ]
)
