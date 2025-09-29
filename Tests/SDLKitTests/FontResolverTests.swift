#if os(Linux)
import Foundation
import XCTest
@testable import SDLKit

final class FontResolverTests: XCTestCase {
    func testSystemDefaultFontResolvesWhenCandidateExists() async throws {
        let fileManager = FileManager.default
        let candidateFiles = [
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
            "/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf"
        ]
        let candidateDirectories = [
            "/usr/share/fonts/truetype",
            "/usr/share/fonts/opentype",
            "/usr/share/fonts",
            "/usr/local/share/fonts"
        ]

        var knownReadableFont: String?
        for path in candidateFiles where fileManager.isReadableFile(atPath: path) {
            knownReadableFont = path
            break
        }

        if knownReadableFont == nil {
            directorySearch: for directory in candidateDirectories {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                    continue
                }
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension.lowercased() == "ttf" && fileManager.isReadableFile(atPath: fileURL.path) {
                        knownReadableFont = fileURL.path
                        break directorySearch
                    }
                }
            }
        }

        guard knownReadableFont != nil else {
            throw XCTSkip("No readable system font candidates available for test")
        }

        let resolved = await MainActor.run { SDLFontResolver.resolve(fontSpec: "system:default") }
        let fontPath = try XCTUnwrap(resolved)
        XCTAssertTrue(fileManager.isReadableFile(atPath: fontPath))
    }
}
#endif
