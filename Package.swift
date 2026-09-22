// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FloatingAgenda",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "FloatingAgenda",
            path: "Sources/FloatingAgenda",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FloatingAgendaTests",
            dependencies: ["FloatingAgenda"],
            path: "Tests/FloatingAgendaTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
