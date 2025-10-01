import Foundation

enum ShaderArtifactMaterializerError: Error, CustomStringConvertible {
    case invalidBase64(url: URL)

    var description: String {
        switch self {
        case .invalidBase64(let url):
            return "Shader artifact base64 payload at \(url.path) could not be decoded"
        }
    }
}

enum ShaderArtifactMaterializer {
    @discardableResult
    static func materializeArtifactIfNeeded(at url: URL) throws -> URL? {
        let fm = FileManager.default
        let artifactPath = url.path
        let base64URL = url.appendingPathExtension("b64")

        var needsDecode = false
        if fm.fileExists(atPath: base64URL.path) {
            if fm.fileExists(atPath: artifactPath) {
                let artifactAttributes = try fm.attributesOfItem(atPath: artifactPath)
                let base64Attributes = try fm.attributesOfItem(atPath: base64URL.path)
                if let artifactDate = artifactAttributes[.modificationDate] as? Date,
                   let base64Date = base64Attributes[.modificationDate] as? Date,
                   artifactDate >= base64Date {
                    return url
                }
            }
            needsDecode = true
        } else if fm.fileExists(atPath: artifactPath) {
            return url
        }

        guard needsDecode else { return nil }

        let base64String = try String(contentsOf: base64URL, encoding: .utf8)
            .filter { !$0.isWhitespace }
        guard let decoded = Data(base64Encoded: base64String) else {
            throw ShaderArtifactMaterializerError.invalidBase64(url: base64URL)
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try decoded.write(to: url, options: .atomic)

        if let base64Attributes = try? fm.attributesOfItem(atPath: base64URL.path),
           let base64Date = base64Attributes[.modificationDate] as? Date {
            try? fm.setAttributes([
                .modificationDate: base64Date
            ], ofItemAtPath: artifactPath)
        }
        return url
    }

    static func materializeArtifactsIfNeeded(at urls: [URL]) throws {
        for url in urls {
            _ = try materializeArtifactIfNeeded(at: url)
        }
    }
}
