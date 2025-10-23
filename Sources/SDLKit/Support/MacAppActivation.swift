import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(CSDL3)
import CSDL3
#endif

@usableFromInline
func SDLKit_activateAppAndWindowIfPossible(_ windowHandle: UnsafeMutableRawPointer?) {
    #if os(macOS)
    guard let windowHandle else { return }
    #if canImport(AppKit)
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)
    if let cocoaPtr = SDLKit_CocoaWindow(windowHandle) {
        let nsWindow = Unmanaged<NSWindow>.fromOpaque(cocoaPtr).takeUnretainedValue()
        nsWindow.center()
        nsWindow.makeKeyAndOrderFront(nil)
        nsWindow.orderFrontRegardless()
    }
    #endif
    #endif
}

