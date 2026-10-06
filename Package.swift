// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoClicker",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AutoClicker", targets: ["AutoClicker"])
    ],
    targets: [
        .executableTarget(
            name: "AutoClicker",
            path: "Sources/AutoClicker",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "AutoClickerTests",
            dependencies: ["AutoClicker"],
            path: "Tests/AutoClickerTests"
        )
    ]
)
