import Foundation

@MainActor
public enum SDLFontRegistry {
    private static var registry: [String: String] = [:] // name -> path

    public static func register(name: String, path: String) {
        registry[name.lowercased()] = path
    }

    public static func path(for name: String) -> String? {
        registry[name.lowercased()]
    }
}

@MainActor
enum SDLFontResolver {
    static func resolve(fontSpec: String?) -> String? {
        if let spec = fontSpec, !spec.isEmpty {
            if spec == "system:default" { return defaultFontPath() }
            if spec.hasPrefix("name:") {
                let key = String(spec.dropFirst("name:".count))
                return SDLFontRegistry.path(for: key)
            }
            return spec // treat as file path
        }
        return defaultFontPath()
    }

    static func defaultFontPath() -> String? {
        #if os(macOS)
        // Try a few common system fonts on macOS (prefer a Unicode-capable font)
        let candidates = [
            "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
            "/System/Library/Fonts/SFNS.ttf",
            "/Library/Fonts/Arial.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttf"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        // Fallback: scan /System/Library/Fonts and /Library/Fonts for a .ttf
        let dirs = ["/System/Library/Fonts", "/Library/Fonts", NSHomeDirectory() + "/Library/Fonts"]
        for dir in dirs {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: dir) {
                if let f = files.first(where: { $0.lowercased().hasSuffix(".ttf") }) {
                    return dir + "/" + f
                }
            }
        }
        return nil
        #else
        return nil
        #endif
    }
}
