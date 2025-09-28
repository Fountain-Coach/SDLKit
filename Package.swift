// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SDLKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SDLKit", targets: ["SDLKit"])
    ],
    targets: [
        .systemLibrary(
            name: "CSDL3",
            pkgConfig: "sdl3",
            providers: [
                .brew(["sdl3"]),
                .apt(["libsdl3-dev"])
            ]
        ),
        .target(
            name: "SDLKit",
            dependencies: ["CSDL3"],
            path: "Sources/SDLKit"
        ),
        .testTarget(
            name: "SDLKitTests",
            dependencies: ["SDLKit"],
            path: "Tests/SDLKitTests"
        )
    ]
)

