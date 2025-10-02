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

public struct SDLLogObserverToken: Hashable, Sendable {
    fileprivate let id: UUID
}

@MainActor
public enum SDLLogger {
    private static let level = SDLLogLevel.fromEnv()
    private static var observers: [UUID: (SDLLogLevel, String, String) -> Void] = [:]

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

    public static func addObserver(_ observer: @escaping (SDLLogLevel, String, String) -> Void) -> SDLLogObserverToken {
        let id = UUID()
        observers[id] = observer
        return SDLLogObserverToken(id: id)
    }

    public static func removeObserver(_ token: SDLLogObserverToken) {
        observers.removeValue(forKey: token.id)
    }

    private static func log(_ lvl: SDLLogLevel, _ component: String, _ msg: @autoclosure () -> String) {
        guard lvl >= level else { return }
        let resolved = msg()
        for observer in observers.values {
            observer(lvl, component, resolved)
        }
        let ts = ISO8601DateFormatter().string(from: Date())
        print("[\(ts)] [\(lvl)] \(component): \(resolved)")
    }
}
