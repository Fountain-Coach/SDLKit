// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "swift-secretstore",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "SecretStore", targets: ["SecretStore"])
    ],
    targets: [
        .target(
            name: "SecretStore"
        ),
        .testTarget(
            name: "SecretStoreTests",
            dependencies: ["SecretStore"]
        )
    ]
)
