#if DEBUG
import SDLKit

struct SDLLogCaptureEntry: Sendable, Equatable {
    let level: SDLLogLevel
    let component: String
    let message: String
}

@MainActor
final class SDLLogCapture {
    private var token: SDLLogObserverToken?
    private(set) var entries: [SDLLogCaptureEntry] = []

    init() {
        token = SDLLogger.addObserver { [weak self] level, component, message in
            self?.entries.append(SDLLogCaptureEntry(level: level, component: component, message: message))
        }
    }

    func stop() {
        if let token {
            SDLLogger.removeObserver(token)
            self.token = nil
        }
    }

}
#endif
