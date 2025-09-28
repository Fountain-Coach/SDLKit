import Foundation

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

    public enum PresentPolicy { case auto, explicit }
}

public enum SDLKitState {
    public static var isTextRenderingEnabled: Bool { false }
}

