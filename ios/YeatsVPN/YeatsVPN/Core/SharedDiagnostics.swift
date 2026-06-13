import Foundation

enum SharedDiagnostics {
    static let appGroupIdentifier = "group.uz.yeats.vpn"
    static let logFileName = "vpn-extension.log"

    static var logFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(logFileName)
    }

    static var statusMessage: String {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return "App Group container is unavailable: \(appGroupIdentifier)"
        }

        let fileURL = containerURL.appendingPathComponent(logFileName)
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        return "App Group OK, extension log \(exists ? "exists" : "missing"): \(fileURL.path)"
    }

    static func readLines() -> [String] {
        guard let logFileURL,
              let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return []
        }
        return content
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
    }

    static func clear() {
        guard let logFileURL else { return }
        try? FileManager.default.removeItem(at: logFileURL)
    }
}
