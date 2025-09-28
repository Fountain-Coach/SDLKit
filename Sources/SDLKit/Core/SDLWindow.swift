// Placeholder for future SDL window wrapper
public final class SDLWindow {
    public struct Config {
        public var title: String
        public var width: Int
        public var height: Int
        public init(title: String, width: Int, height: Int) {
            self.title = title; self.width = width; self.height = height
        }
    }

    public let config: Config
    public init(config: Config) { self.config = config }

    public func open() throws { /* TODO: call SDL_CreateWindow */ }
    public func close() { /* TODO: call SDL_DestroyWindow */ }
}

