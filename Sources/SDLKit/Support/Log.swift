import Foundation

public enum SDLLogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3

    public static func < (lhs: SDLLogLevel, rhs: SDLLogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    static func fromEnv() -> SDLLogLevel {
        let env = ProcessInfo.processInfo.environment["SDLKIT_LOG_LEVEL"]?.lowercased()
        switch env {
        case "debug": return .debug
        case "info": return .info
        case "warn": return .warn
        case "error": return .error
        default: return .info
        }
    }
}

@MainActor
public enum SDLLogger {
    private static let level = SDLLogLevel.fromEnv()

    public static func debug(_ component: String, _ msg: @autoclosure () -> String) {
        log(.debug, component, msg())
    }
    public static func info(_ component: String, _ msg: @autoclosure () -> String) {
        log(.info, component, msg())
    }
    public static func warn(_ component: String, _ msg: @autoclosure () -> String) {
        log(.warn, component, msg())
    }
    public static func error(_ component: String, _ msg: @autoclosure () -> String) {
        log(.error, component, msg())
    }

    private static func log(_ lvl: SDLLogLevel, _ component: String, _ msg: @autoclosure () -> String) {
        guard lvl >= level else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        print("[\(ts)] [\(lvl)] \(component): \(msg())")
    }
}
