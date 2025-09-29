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

