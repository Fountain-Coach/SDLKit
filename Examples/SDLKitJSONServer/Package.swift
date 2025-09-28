// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SDLKitJSONServer",
    platforms: [ .macOS(.v13) ],
    products: [ .executable(name: "SDLKitJSONServer", targets: ["SDLKitJSONServer"]) ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0"),
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "SDLKitJSONServer",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "SDLKit", package: "SDLKit")
            ],
            path: "Sources"
        )
    ]
)

