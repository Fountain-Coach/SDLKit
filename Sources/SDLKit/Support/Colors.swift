import Foundation

public enum SDLColor {
    public enum ParseError: Error { case invalidFormat(String) }

    // Parses color strings in forms: "#RRGGBB", "#AARRGGBB", "0xRRGGBB", "0xAARRGGBB",
    // or named colors (limited set). Returns ARGB as 0xAARRGGBB.
    public static func parse(_ value: String) throws -> UInt32 {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let named = namedColors[trimmed] { return named }

        var hex = trimmed
        if hex.hasPrefix("#") { hex.removeFirst() }
        else if hex.hasPrefix("0x") { hex.removeFirst(2) }

        guard hex.allSatisfy({ $0.isHexDigit }) else { throw ParseError.invalidFormat(value) }

        switch hex.count {
        case 6: // RRGGBB -> assume opaque
            guard let rgb = UInt32(hex, radix: 16) else { throw ParseError.invalidFormat(value) }
            return 0xFF00_0000 | rgb
        case 8: // AARRGGBB
            guard let argb = UInt32(hex, radix: 16) else { throw ParseError.invalidFormat(value) }
            return argb
        default:
            throw ParseError.invalidFormat(value)
        }
    }

    // Map a few common names to ARGB
    private static let namedColors: [String: UInt32] = [
        "black": 0xFF000000,
        "white": 0xFFFFFFFF,
        "red":   0xFFFF0000,
        "green": 0xFF00FF00,
        "blue":  0xFF0000FF,
        "gray":  0xFF808080,
        "grey":  0xFF808080,
        "yellow":0xFFFFFF00,
        "cyan":  0xFF00FFFF,
        "magenta":0xFFFF00FF
    ]
}

