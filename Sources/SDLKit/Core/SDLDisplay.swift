import Foundation
#if !HEADLESS_CI && canImport(CSDL3)
import CSDL3
#endif

@MainActor
enum SDLDisplay {
    struct Summary: Codable { let id: Int; let name: String }
    struct Bounds: Codable { let x: Int; let y: Int; let width: Int; let height: Int }

    static func list() throws -> [Summary] {
        #if !HEADLESS_CI && canImport(CSDL3)
        let n = SDLKit_GetNumVideoDisplays()
        guard n >= 0 else { throw AgentError.internalError(SDLCore.lastError()) }
        var out: [Summary] = []
        for i in 0..<n {
            let cname = SDLKit_GetDisplayName(i)
            let name = cname != nil ? String(cString: cname!) : "display_\(i)"
            out.append(Summary(id: Int(i), name: name))
        }
        return out
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    static func getInfo(index: Int) throws -> Bounds {
        #if !HEADLESS_CI && canImport(CSDL3)
        var x: Int32 = 0, y: Int32 = 0, w: Int32 = 0, h: Int32 = 0
        if SDLKit_GetDisplayBounds(Int32(index), &x, &y, &w, &h) != 0 { throw AgentError.internalError(SDLCore.lastError()) }
        return Bounds(x: Int(x), y: Int(y), width: Int(w), height: Int(h))
        #else
        throw AgentError.sdlUnavailable
        #endif
    }
}

