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

        var env = ProcessInfo.processInfo.environment
        let shaderEnvURL = context.package.directoryURL.appendingPathComponent(".fountain/sdlkit/shader-tools.env")
        if let data = try? Data(contentsOf: shaderEnvURL), let text = String(data: data, encoding: .utf8) {
            for rawLine in text.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty || line.hasPrefix("#") { continue }
                if let eqIdx = line.firstIndex(of: "=") {
                    let key = String(line[..<eqIdx])
                    let val = String(line[line.index(after: eqIdx)...])
                    env[key] = val
                }
            }
        }
        return [
            .prebuildCommand(
                displayName: "Compile SDLKit shaders",
                executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["python3", scriptPath.path, context.package.directoryURL.path, outputDir.path],
                environment: env,
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
