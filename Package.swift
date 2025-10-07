// swift-tools-version: 6.1
import PackageDescription
import Foundation

#if os(Linux)
let isLinux = true
#else
let isLinux = false
#endif

let env = ProcessInfo.processInfo.environment
let useYams = (env["SDLKIT_NO_YAMS"] ?? "0") != "1"
let guiEnabled: Bool = {
    let raw = (env["SDLKIT_GUI_ENABLED"] ?? "true").lowercased()
    return !(raw == "0" || raw == "false")
}()

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
let hasVulkan = pkgConfigExists("vulkan")

if isLinux && !hasVulkan {
    fatalError("""
    Vulkan development files are required to build SDLKit on Linux. Install the Vulkan SDK (headers, loader, and validation layers) via your distribution's package manager—for example `sudo apt install libvulkan-dev vulkan-validationlayers` on Debian/Ubuntu—then re-run the build.
    """)
}

let package = Package(
    name: "SDLKit",
    platforms: [
        .macOS(.v13)
    ],
    products: {
        var prods: [Product] = [
            .library(name: "SDLKit", targets: ["SDLKit"]) 
        ]
        if guiEnabled {
            prods.append(.executable(name: "SDLKitDemo", targets: ["SDLKitDemo"]))
        }
        return prods
    }(),
    dependencies: {
        var deps: [Package.Dependency] = []
        if useYams {
            deps.append(.package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"))
        }
        // FountainStore for persistence (golden references, configs, etc.)
        deps.append(.package(path: "External/Fountain-Store"))
        // SecretStore for secure secret persistence
        deps.append(.package(path: "External/swift-secretstore"))
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
            // Small C compat layer for tricky symbols (property pointers, TTF text helpers)
            targets.append(
                .target(
                    name: "CSDL3Compat",
                    path: "Sources/CSDL3Compat",
                    publicHeadersPath: "."
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

        if guiEnabled {
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
        }

        if guiEnabled {
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
        }

        targets.append(
            .target(
                name: "SDLKit",
                dependencies: {
                    var deps: [Target.Dependency] = [ "CSDL3" ]
                    // Only include SDL_image shims when GUI is enabled
                    if guiEnabled {
                        deps.append(.target(name: "CSDL3IMAGE", condition: .when(platforms: [.macOS, .linux])))
                        if hasSDL3TTF {
                            deps.append(.target(name: "CSDL3TTF", condition: .when(platforms: [.macOS, .linux])))
                        }
                        if hasSDL3 {
                            deps.append(.target(name: "CSDL3Compat", condition: .when(platforms: [.macOS, .linux])))
                        }
                    }
                    if isLinux {
                        deps.append(.target(name: "CVulkan", condition: .when(platforms: [.linux])))
                    }
                    if useYams { deps.append(.product(name: "Yams", package: "Yams")) }
                    // Persist golden image references and other settings
                    deps.append(.product(name: "FountainStore", package: "Fountain-Store"))
                    // Secrets
                    deps.append(.product(name: "SecretStore", package: "swift-secretstore"))
                    return deps
                }(),
                path: "Sources/SDLKit",
                resources: [
                    .copy("Generated")
                ],
                cSettings: {
                    var flags: [CSetting] = []
                    if let inc = env["SDL3_INCLUDE_DIR"], !inc.isEmpty {
                        flags.append(.unsafeFlags(["-I\(inc)"]))
                    }
                    return flags
                }(),
                swiftSettings: {
                    var defs: [SwiftSetting] = []
                    if useYams { defs.append(.define("OPENAPI_USE_YAMS")) }
                    // If system SDL3 is not available, compile in headless mode to avoid referencing SDL types.
                    if !hasSDL3 { defs.append(.define("HEADLESS_CI")) }
                    return defs
                }(),
                linkerSettings: {
                    var flags: [LinkerSetting] = []
                    if let lib = env["SDL3_LIB_DIR"], !lib.isEmpty {
                        flags.append(.unsafeFlags(["-L\(lib)"]))
                    }
                    return flags
                }(),
                plugins: [
                    .plugin(name: "ShaderBuildPlugin")
                ]
            )
        )

        if isLinux {
            targets.append(
                .systemLibrary(
                    name: "CVulkan",
                    pkgConfig: "vulkan",
                    providers: [
                        .apt(["libvulkan-dev"]) // Linux
                    ]
                )
            )
        }

        if isLinux {
            targets.append(
                .target(
                    name: "VulkanMinimal",
                    path: "Sources/VulkanMinimal",
                    publicHeadersPath: "include"
                )
            )
        }

        if guiEnabled {
            targets.append(
                .target(
                    name: "SDLKitTTF",
                    dependencies: ["SDLKit", "CSDL3TTF"],
                    path: "Sources/SDLKitTTF"
                )
            )
        }

        targets.append(
            .testTarget(
                name: "SDLKitTests",
                dependencies: {
                    var deps: [Target.Dependency] = [
                        "SDLKit",
                        .product(name: "FountainStore", package: "Fountain-Store")
                    ]
                    // C shim types used in tests (SDL_Renderer/SDL_Texture)
                    deps.append("CSDL3")
                    return deps
                }(),
                path: "Tests/SDLKitTests"
            )
        )

        targets.append(
            .testTarget(
                name: "SDLKitGraphicsTests",
                dependencies: ["SDLKit"],
                path: "Tests/SDLKitGraphicsTests"
            )
        )

        if guiEnabled {
            targets.append(
                .executableTarget(
                    name: "SDLKitDemo",
                    dependencies: {
                        var deps: [Target.Dependency] = [ "SDLKit" ]
                        deps.append(.target(name: "SDLKitTTF", condition: .when(platforms: [.macOS, .linux])))
                        if isLinux {
                            deps.append(.target(name: "VulkanMinimal", condition: .when(platforms: [.linux])))
                        }
                        return deps
                    }(),
                    path: "Sources/SDLKitDemo"
                )
            )
        }

        targets.append(
            .executableTarget(
                name: "SDLKitGolden",
                dependencies: [
                    "SDLKit",
                    .product(name: "FountainStore", package: "Fountain-Store")
                ],
                path: "Sources/SDLKitGolden"
            )
        )

        targets.append(
            .executableTarget(
                name: "SDLKitSettings",
                dependencies: ["SDLKit", .product(name: "FountainStore", package: "Fountain-Store")],
                path: "Sources/SDLKitSettings"
            )
        )

        targets.append(
            .executableTarget(
                name: "SDLKitMigrate",
                dependencies: ["SDLKit", .product(name: "FountainStore", package: "Fountain-Store"), .product(name: "SecretStore", package: "swift-secretstore")],
                path: "Sources/SDLKitMigrate"
            )
        )

        targets.append(
            .plugin(
                name: "ShaderBuildPlugin",
                capability: .buildTool()
            )
        )

        return targets
    }()
)
