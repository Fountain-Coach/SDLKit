import Foundation
import SDLKit

@main
struct SDLKitMigrateCLI {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        var changes: [(String, String)] = []

        func migrateString(envKey: String, settingsKey: String) {
            if let v = env[envKey], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SettingsStore.setString(settingsKey, v)
                changes.append((settingsKey, v))
            }
        }
        func migrateBool(envKey: String, settingsKey: String) {
            if let v = env[envKey]?.lowercased() {
                if ["1","true","yes","on"].contains(v) { SettingsStore.setBool(settingsKey, true); changes.append((settingsKey, "1")) }
                if ["0","false","no","off"].contains(v) { SettingsStore.setBool(settingsKey, false); changes.append((settingsKey, "0")) }
            }
        }

        // Rendering
        migrateString(envKey: "SDLKIT_RENDER_BACKEND", settingsKey: SDLKitConfigStore.Keys.renderBackendOverride)
        migrateString(envKey: "SDLKIT_PRESENT_POLICY", settingsKey: SDLKitConfigStore.Keys.presentPolicy)
        migrateBool(envKey: "SDLKIT_VK_VALIDATION", settingsKey: SDLKitConfigStore.Keys.vkValidation)
        migrateBool(envKey: "SDLKIT_DX12_DEBUG_LAYER", settingsKey: "dx12.debug_layer")

        // Scene defaults
        migrateString(envKey: "SDLKIT_SCENE_MATERIAL", settingsKey: SDLKitConfigStore.Keys.sceneDefaultMaterial)
        migrateString(envKey: "SDLKIT_SCENE_BASE_COLOR", settingsKey: SDLKitConfigStore.Keys.sceneDefaultBaseColor)
        migrateString(envKey: "SDLKIT_SCENE_LIGHT_DIR", settingsKey: SDLKitConfigStore.Keys.sceneDefaultLightDir)
        migrateBool(envKey: "SDLKIT_DEMO_FORCE_2D", settingsKey: "demo.force2d")

        // Shader toolchain & root
        migrateString(envKey: "SDLKIT_SHADER_ROOT", settingsKey: "shader.root")
        migrateString(envKey: "SDLKIT_SHADER_DXC", settingsKey: "shader.dxc.path")
        migrateString(envKey: "SDLKIT_SHADER_SPIRV_CROSS", settingsKey: "shader.spirv_cross.path")
        migrateString(envKey: "SDLKIT_SHADER_METAL", settingsKey: "shader.metal.path")
        migrateString(envKey: "SDLKIT_SHADER_METALLIB", settingsKey: "shader.metallib.path")

        // Golden flow
        migrateBool(envKey: "SDLKIT_GOLDEN_AUTO_WRITE", settingsKey: SDLKitConfigStore.Keys.goldenAutoWrite)

        // Print summary JSON
        var dict: [String: String] = [:]
        for (k,v) in changes { dict[k] = v }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .prettyPrinted]) {
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("{}")
        }
    }
}

