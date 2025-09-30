// swift-tools-version: 6.1
import Foundation
import PackagePlugin
#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin
#endif

@main
struct ShaderBuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let swiftTarget = target as? SwiftSourceModuleTarget else { return [] }
        // Only build shaders for the main SDLKit target to avoid redundant invocations.
        guard swiftTarget.moduleName == "SDLKit" else { return [] }

        let outputDir = context.pluginWorkDirectoryURL.appendingPathComponent("ShaderBuild", isDirectory: true)
        let scriptPath = context.package.directoryURL.appendingPathComponent("Scripts/ShaderBuild/build-shaders.py")

        return [
            .prebuildCommand(
                displayName: "Compile SDLKit shaders",
                executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["python3", scriptPath.path, context.package.directoryURL.path, outputDir.path],
                environment: [:],
                outputFilesDirectory: outputDir
            )
        ]
    }
}

#if canImport(XcodeProjectPlugin)
extension ShaderBuildPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let packagePluginContext = try PluginContext(
            package: context.package,
            pluginWorkDirectory: context.pluginWorkDirectory,
            toolNamesToPaths: [:]
        )
        return try createBuildCommands(context: packagePluginContext, target: target)
    }
}
#endif
