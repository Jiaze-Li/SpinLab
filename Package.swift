// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpinLab",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "SpinLabApp",
            targets: ["SpinLabApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.0")
    ],
    targets: [
        .executableTarget(
            name: "SpinLabApp",
            dependencies: [
                "CoreXLSX"
            ],
            path: "Sources/SpinLabApp",
            resources: [
                .process("config")
            ]
        ),
        .testTarget(
            name: "SpinLabAppTests",
            dependencies: ["SpinLabApp"],
            path: "Tests/SpinLabAppTests"
        )
    ]
)
