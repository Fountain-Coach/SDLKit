import Foundation

// High-level typed accessors over SettingsStore and Secrets for SDLKit defaults.
public enum SDLKitConfigStore {
    // MARK: - Keys
    public enum Keys {
        // Rendering
        public static let renderBackendOverride = "render.backend.override"          // String: metal|d3d12|vulkan
        public static let presentPolicy = "present.policy"                           // String: auto|explicit
        public static let vkValidation = "vk.validation"                             // Bool
        // Scene defaults
        public static let sceneDefaultMaterial = "scene.default.material"             // String: unlit|basic_lit
        public static let sceneDefaultBaseColor = "scene.default.baseColor"           // String: "r,g,b,a" floats
        public static let sceneDefaultLightDir = "scene.default.lightDirection"       // String: "x,y,z" floats
        // Golden image controls
        public static let goldenLastKey = "golden.last.key"                           // String
        public static let goldenAutoWrite = "golden.auto.write"                       // Bool
    }

    // MARK: - Scene helpers
    public static func defaultMaterial() -> String {
        SettingsStore.getString(Keys.sceneDefaultMaterial) ?? "basic_lit"
    }

    public static func defaultBaseColor() -> (Float, Float, Float, Float)? {
        guard let s = SettingsStore.getString(Keys.sceneDefaultBaseColor) else { return nil }
        return parseVec4(s)
    }

    public static func defaultLightDirection() -> (Float, Float, Float)? {
        // Prefer secret override if present
        if let data = try? Secrets.retrieve(key: "light_dir"), let s = data.flatMap({ String(data: $0, encoding: .utf8) }) {
            if let v = parseVec3(s) { return v }
        }
        if let s = SettingsStore.getString(Keys.sceneDefaultLightDir) { return parseVec3(s) }
        return nil
    }

    // MARK: - Utilities
    public static func parseVec3(_ s: String) -> (Float, Float, Float)? {
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3, let x = Float(parts[0]), let y = Float(parts[1]), let z = Float(parts[2]) else { return nil }
        return (x, y, z)
    }
    public static func parseVec4(_ s: String) -> (Float, Float, Float, Float)? {
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 4, let x = Float(parts[0]), let y = Float(parts[1]), let z = Float(parts[2]), let w = Float(parts[3]) else { return nil }
        return (x, y, z, w)
    }
}

