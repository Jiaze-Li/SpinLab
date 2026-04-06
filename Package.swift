// swift-tools-version: 6.0
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
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.0"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4")
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
            dependencies: [
                "SpinLabApp",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/SpinLabAppTests",
            exclude: [
                "README.md"
            ],
            resources: [
                .copy("TestData")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
