// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MasteryMemory",
    platforms: [.iOS(.v17), .macOS(.v12)],
    products: [
        .library(name: "MasteryMemory", targets: ["MasteryMemory"]),
    ],
    targets: [
        .target(
            name: "MasteryMemory",
            path: "Sources/MasteryMemory"
        ),
        .testTarget(
            name: "MasteryMemoryTests",
            dependencies: ["MasteryMemory"],
            path: "Tests/MasteryMemoryTests"
        ),
    ]
)
