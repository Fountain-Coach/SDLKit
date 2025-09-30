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
        guard let raw = ProcessInfo.processInfo.environment["SDLKIT_RENDER_BACKEND"] else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static var demoForceLegacy2D: Bool {
        guard let raw = ProcessInfo.processInfo.environment["SDLKIT_DEMO_FORCE_2D"] else {
            return false
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes"
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

