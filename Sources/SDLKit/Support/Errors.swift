public enum AgentError: Error, Equatable {
    case windowNotFound
    case sdlUnavailable
    case notImplemented
    case invalidArgument(String)
    case internalError(String)
    case deviceLost(String)
}

