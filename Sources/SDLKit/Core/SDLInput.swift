import Foundation
#if !HEADLESS_CI && canImport(CSDL3)
import CSDL3
#endif

@MainActor
enum SDLInput {
    struct KeyboardModifiers: Codable { let shift: Bool; let ctrl: Bool; let alt: Bool; let gui: Bool }
    struct MouseState: Codable { let x: Int; let y: Int; let buttons: [Int] }

    static func getKeyboardModifiers() throws -> KeyboardModifiers {
        #if !HEADLESS_CI && canImport(CSDL3)
        let mask = SDLKit_GetModMask()
        // Best-effort mapping; exact mask bits are provided by SDL
        let shift = (mask & (1 << 0)) != 0 || (mask & (1 << 1)) != 0 // L/R shift
        let ctrl  = (mask & (1 << 2)) != 0 || (mask & (1 << 3)) != 0 // L/R ctrl
        let alt   = (mask & (1 << 4)) != 0 || (mask & (1 << 5)) != 0 // L/R alt
        let gui   = (mask & (1 << 6)) != 0 || (mask & (1 << 7)) != 0 // L/R GUI
        return KeyboardModifiers(shift: shift, ctrl: ctrl, alt: alt, gui: gui)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }

    static func getMouseState() throws -> MouseState {
        #if !HEADLESS_CI && canImport(CSDL3)
        var x: Int32 = 0, y: Int32 = 0
        var b: UInt32 = 0
        SDLKit_GetMouseState(&x, &y, &b)
        var pressed: [Int] = []
        for i in 1...8 { // report first few buttons
            if (b & (1 << (i - 1))) != 0 { pressed.append(i) }
        }
        return MouseState(x: Int(x), y: Int(y), buttons: pressed)
        #else
        throw AgentError.sdlUnavailable
        #endif
    }
}

