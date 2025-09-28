// swift-tools-version: 5.9
import PackageDescription
import Foundation

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
            path: "Sources/SDLKit",
            cSettings: {
                var flags: [CSetting] = []
                let env = ProcessInfo.processInfo.environment
                if let inc = env["SDL3_INCLUDE_DIR"], !inc.isEmpty {
                    flags.append(.unsafeFlags(["-I\(inc)"]))
                }
                return flags
            }(),
            linkerSettings: {
                var flags: [LinkerSetting] = []
                let env = ProcessInfo.processInfo.environment
                if let lib = env["SDL3_LIB_DIR"], !lib.isEmpty {
                    flags.append(.unsafeFlags(["-L\(lib)"]))
                }
                return flags
            }()
        ),
        .testTarget(
            name: "SDLKitTests",
            dependencies: ["SDLKit"],
            path: "Tests/SDLKitTests"
        )
    ]
)
