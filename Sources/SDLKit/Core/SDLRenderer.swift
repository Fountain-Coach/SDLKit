// Placeholder for future SDL renderer wrapper
public final class SDLRenderer {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int /*, for window: SDLWindow */) {
        self.width = width
        self.height = height
    }

    public func present() { /* TODO: SDL_RenderPresent */ }
}

