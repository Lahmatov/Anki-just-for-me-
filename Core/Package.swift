// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AJFMCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AJFMCore", targets: ["AJFMCore"])
    ],
    targets: [
        .target(name: "AJFMCore"),
        .testTarget(
            name: "AJFMCoreTests",
            dependencies: ["AJFMCore"],
            resources: [.copy("Resources")]
        )
    ]
)
