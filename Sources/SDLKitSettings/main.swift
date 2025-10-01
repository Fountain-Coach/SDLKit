import Foundation
import SDLKit

@main
struct SDLKitSettingsCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else { return printUsage() }
        var key: String?
        var value: String?
        var it = args.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--key", "-k": key = it.next()
            case "--value", "-v": value = it.next()
            default: break
            }
        }
        switch cmd {
        case "get":
            guard let k = key else { return printUsage() }
            if let s = SettingsStore.getString(k) { print(s) } else { print("") }
        case "set":
            guard let k = key, let v = value else { return printUsage() }
            SettingsStore.setString(k, v)
            print("OK")
        case "set-bool":
            guard let k = key, let v = value else { return printUsage() }
            let b = ["1","true","yes","on"].contains(v.lowercased())
            SettingsStore.setBool(k, b)
            print("OK")
        case "list":
            // List known keys and current values
            let known: [(String, String?)] = [
                (SDLKitConfigStore.Keys.renderBackendOverride, SettingsStore.getString(SDLKitConfigStore.Keys.renderBackendOverride)),
                (SDLKitConfigStore.Keys.presentPolicy, SettingsStore.getString(SDLKitConfigStore.Keys.presentPolicy)),
                (SDLKitConfigStore.Keys.vkValidation, SettingsStore.getBool(SDLKitConfigStore.Keys.vkValidation).map { $0 ? "1" : "0" }),
                (SDLKitConfigStore.Keys.sceneDefaultMaterial, SettingsStore.getString(SDLKitConfigStore.Keys.sceneDefaultMaterial)),
                (SDLKitConfigStore.Keys.sceneDefaultBaseColor, SettingsStore.getString(SDLKitConfigStore.Keys.sceneDefaultBaseColor)),
                (SDLKitConfigStore.Keys.sceneDefaultLightDir, SettingsStore.getString(SDLKitConfigStore.Keys.sceneDefaultLightDir)),
                (SDLKitConfigStore.Keys.goldenLastKey, SettingsStore.getString(SDLKitConfigStore.Keys.goldenLastKey)),
                (SDLKitConfigStore.Keys.goldenAutoWrite, SettingsStore.getBool(SDLKitConfigStore.Keys.goldenAutoWrite).map { $0 ? "1" : "0" })
            ]
            for (k,v) in known {
                print("\(k)=\(v ?? "<unset>")")
            }
        case "dump":
            // Dump all settings as JSON
            let all = SettingsStore.dumpAll()
            if let data = try? JSONSerialization.data(withJSONObject: all, options: [.sortedKeys, .prettyPrinted]) {
                print(String(data: data, encoding: .utf8) ?? "{}")
            } else {
                print("{}")
            }
        case "env":
            // Print export lines for shader toolchain overrides if present
            let dxc = SettingsStore.getString("shader.dxc.path")
            let sc = SettingsStore.getString("shader.spirv_cross.path")
            let metal = SettingsStore.getString("shader.metal.path")
            let metallib = SettingsStore.getString("shader.metallib.path")
            if let dxc { print("export SDLKIT_SHADER_DXC=\(dxc)") }
            if let sc { print("export SDLKIT_SHADER_SPIRV_CROSS=\(sc)") }
            if let metal { print("export SDLKIT_SHADER_METAL=\(metal)") }
            if let metallib { print("export SDLKIT_SHADER_METALLIB=\(metallib)") }
        case "write-env":
            // Write .fountain/sdlkit/shader-tools.env for the plugin to read
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            let dir = cwd.appendingPathComponent(".fountain/sdlkit", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("shader-tools.env")
            var lines: [String] = []
            func add(_ key: String, _ envKey: String) {
                if let v = SettingsStore.getString(key), !v.isEmpty { lines.append("\(envKey)=\(v)") }
            }
            add("shader.dxc.path", "SDLKIT_SHADER_DXC")
            add("shader.spirv_cross.path", "SDLKIT_SHADER_SPIRV_CROSS")
            add("shader.metal.path", "SDLKIT_SHADER_METAL")
            add("shader.metallib.path", "SDLKIT_SHADER_METALLIB")
            let content = lines.joined(separator: "\n") + "\n"
            try? content.data(using: .utf8)?.write(to: file)
            print("Wrote \(file.path)")
        default:
            printUsage()
        }
    }

    static func printUsage() {
        print("""
        Usage: sdlkit-settings <get|set|set-bool|list|dump|env|write-env> --key KEY [--value VALUE]
        Examples:
          sdlkit-settings set --key render.backend.override --value metal
          sdlkit-settings set-bool --key vk.validation --value true
          sdlkit-settings list
          sdlkit-settings dump
          sdlkit-settings env       # prints export lines for shader toolchain envs
          sdlkit-settings write-env # writes .fountain/sdlkit/shader-tools.env
        """)
    }
}
