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
        #elseif os(Linux)
        let fileManager = FileManager.default
        // Search order:
        // 1. Known, widely available fonts such as DejaVu Sans and Liberation Sans.
        // 2. Common font directories (e.g., /usr/share/fonts) scanned depth-first for a readable .ttf.
        let candidateFiles = [
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
            "/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf"
        ]
        for path in candidateFiles {
            if fileManager.isReadableFile(atPath: path) {
                return path
            }
        }

        let candidateDirectories = [
            "/usr/share/fonts/truetype",
            "/usr/share/fonts/opentype",
            "/usr/share/fonts",
            "/usr/local/share/fonts"
        ]
        for directory in candidateDirectories {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else { continue }

            let url = URL(fileURLWithPath: directory, isDirectory: true)
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension.lowercased() == "ttf" && fileManager.isReadableFile(atPath: fileURL.path) {
                        return fileURL.path
                    }
                }
            }
        }
        return nil
        #else
        return nil
        #endif
    }
}
