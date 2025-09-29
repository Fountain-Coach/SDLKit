// swift-tools-version: 6.1
import PackageDescription
import Foundation

let env = ProcessInfo.processInfo.environment
let useYams = (env["SDLKIT_NO_YAMS"] ?? "0") != "1"

func pkgConfigExists(_ package: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["pkg-config", "--exists", package]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

let forceStub = (env["SDLKIT_FORCE_HEADLESS"] ?? "0") == "1"
let forceSystem = (env["SDLKIT_FORCE_SYSTEM_SDL"] ?? "0") == "1"

func shouldUseSystemPackage(_ pkg: String) -> Bool {
    if forceStub { return false }
    if forceSystem { return true }
    return pkgConfigExists(pkg)
}

let hasSDL3 = shouldUseSystemPackage("sdl3")
let hasSDL3Image = shouldUseSystemPackage("sdl3-image")
let hasSDL3TTF = shouldUseSystemPackage("sdl3-ttf")

let package = Package(
    name: "SDLKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SDLKit", targets: ["SDLKit"]),
        .executable(name: "SDLKitDemo", targets: ["SDLKitDemo"])
    ],
    dependencies: {
        var deps: [Package.Dependency] = []
        if useYams {
            deps.append(.package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"))
        }
        return deps
    }(),
    targets: {
        var targets: [Target] = []

        if hasSDL3 {
            targets.append(
                .systemLibrary(
                    name: "CSDL3",
                    pkgConfig: "sdl3",
                    providers: [
                        .brew(["sdl3"]),
                        .apt(["libsdl3-dev"])
                    ]
                )
            )
        } else {
            targets.append(
                .target(
                    name: "CSDL3",
                    path: "Sources/CSDL3Stub",
                    publicHeadersPath: "include"
                )
            )
        }

        if hasSDL3Image {
            targets.append(
                .systemLibrary(
                    name: "CSDL3IMAGE",
                    pkgConfig: "sdl3-image",
                    providers: [
                        .brew(["sdl3_image"]),
                        .apt(["libsdl3-image-dev"])
                    ]
                )
            )
        } else {
            targets.append(
                .target(
                    name: "CSDL3IMAGE",
                    path: "Sources/CSDL3ImageStub",
                    publicHeadersPath: "include"
                )
            )
        }

        if hasSDL3TTF {
            targets.append(
                .systemLibrary(
                    name: "CSDL3TTF",
                    pkgConfig: "sdl3-ttf",
                    providers: [
                        .brew(["sdl3_ttf"]),
                        .apt(["libsdl3-ttf-dev"])
                    ]
                )
            )
        } else {
            targets.append(
                .target(
                    name: "CSDL3TTF",
                    path: "Sources/CSDL3TTFStub",
                    publicHeadersPath: "include"
                )
            )
        }

        targets.append(
            .target(
                name: "SDLKit",
                dependencies: {
                    var deps: [Target.Dependency] = [
                        "CSDL3",
                        .target(name: "CSDL3IMAGE", condition: .when(platforms: [.macOS, .linux]))
                    ]
                    if useYams { deps.append(.product(name: "Yams", package: "Yams")) }
                    return deps
                }(),
                path: "Sources/SDLKit",
                cSettings: {
                    var flags: [CSetting] = []
                    if let inc = env["SDL3_INCLUDE_DIR"], !inc.isEmpty {
                        flags.append(.unsafeFlags(["-I\(inc)"]))
                    }
                    // Fallback common include roots
                    flags.append(.unsafeFlags(["-I/usr/local/include"]))
                    flags.append(.unsafeFlags(["-I/usr/include"]))
                    return flags
                }(),
                swiftSettings: useYams ? [ .define("OPENAPI_USE_YAMS") ] : [],
                linkerSettings: {
                    var flags: [LinkerSetting] = []
                    if let lib = env["SDL3_LIB_DIR"], !lib.isEmpty {
                        flags.append(.unsafeFlags(["-L\(lib)"]))
                    }
                    // Fallback common lib roots
                    flags.append(.unsafeFlags(["-L/usr/local/lib"]))
                    return flags
                }()
            )
        )

        targets.append(
            .target(
                name: "SDLKitTTF",
                dependencies: ["SDLKit", "CSDL3TTF"],
                path: "Sources/SDLKitTTF"
            )
        )

        targets.append(
            .testTarget(
                name: "SDLKitTests",
                dependencies: ["SDLKit"],
                path: "Tests/SDLKitTests"
            )
        )

        targets.append(
            .executableTarget(
                name: "SDLKitDemo",
                dependencies: ["SDLKit"],
                path: "Sources/SDLKitDemo"
            )
        )

        return targets
    }()
)
