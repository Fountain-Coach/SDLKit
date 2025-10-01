import Foundation

#if !HEADLESS_CI && canImport(CSDL3)
import CSDL3
#endif

public enum SDLKitConfig {
    public static var guiEnabled: Bool {
        let env = ProcessInfo.processInfo.environment["SDLKIT_GUI_ENABLED"]?.lowercased()
        if let env { return env != "0" && env != "false" }
        return true
    }

    public static var presentPolicy: PresentPolicy {
        if let s = SettingsStore.getString("present.policy")?.lowercased() {
            return s == "auto" ? .auto : .explicit
        }
        let env = ProcessInfo.processInfo.environment["SDLKIT_PRESENT_POLICY"]?.lowercased()
        return env == "auto" ? .auto : .explicit
    }

    public static var maxWindows: Int {
        let defaultValue = 8
        guard let raw = ProcessInfo.processInfo.environment["SDLKIT_MAX_WINDOWS"] else {
            return defaultValue
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed), parsed > 0 else {
            return defaultValue
        }
        return parsed
    }

    public static var renderBackendOverride: String? {
        // Prefer persisted setting; fallback to env
        if let s = SettingsStore.getString("render.backend.override"), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        if let raw = ProcessInfo.processInfo.environment["SDLKIT_RENDER_BACKEND"] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    public static var demoForceLegacy2D: Bool {
        if let persisted = SettingsStore.getBool("demo.force2d") { return persisted }
        if let raw = ProcessInfo.processInfo.environment["SDLKIT_DEMO_FORCE_2D"] {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return value == "1" || value == "true" || value == "yes"
        }
        return false
    }

    public enum PresentPolicy { case auto, explicit }
}

public enum SDLKitState {
    #if !HEADLESS_CI && canImport(CSDL3)
    private static let cachedTextRenderingEnabled: Bool = {
        SDLKit_TTF_Available() != 0
    }()
    #endif

    public static var isTextRenderingEnabled: Bool {
        #if HEADLESS_CI
        return false
        #elseif canImport(CSDL3)
        return cachedTextRenderingEnabled
        #else
        return false
        #endif
    }
}
