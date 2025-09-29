import Foundation
#if !HEADLESS_CI && canImport(CSDL3)
import CSDL3
#endif

@MainActor
enum SDLClipboard {
    static func getText() throws -> String {
        #if !HEADLESS_CI && canImport(CSDL3)
        guard let p = SDLKit_GetClipboardText() else { return "" }
        defer { SDLKit_free(p) }
        return String(cString: p)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    static func setText(_ text: String) throws {
        #if !HEADLESS_CI && canImport(CSDL3)
        let rc = text.withCString { cstr in SDLKit_SetClipboardText(cstr) }
        if rc != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        #else
        throw AgentError.sdlUnavailable
        #endif
    }
}

