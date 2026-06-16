import Foundation

enum SharedDiagnostics {
    static let appGroupIdentifier = "group.uz.yeats.vpn"
    static let logFileName = "vpn-extension.log"
    static let phaseFileName = "vpn-extension-phase.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var logFileURL: URL? {
        containerURL?.appendingPathComponent(logFileName)
    }

    static var phaseFileURL: URL? {
        containerURL?.appendingPathComponent(phaseFileName)
    }

    static var statusMessage: String {
        guard let containerURL else {
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

    // MARK: - Extension Startup Phase (crash-resilient)

    struct ExtensionPhase: Codable {
        let phase: String
        let error: String?
        let timestamp: String
    }

    static func writePhase(_ phase: String, error: String? = nil) {
        guard let phaseFileURL else { return }
        let value = ExtensionPhase(
            phase: phase,
            error: error,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: phaseFileURL, options: [.atomic])
    }

    static func readPhase() -> ExtensionPhase? {
        guard let phaseFileURL,
              let data = try? Data(contentsOf: phaseFileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(ExtensionPhase.self, from: data)
    }

    static func clearPhase() {
        guard let phaseFileURL else { return }
        try? FileManager.default.removeItem(at: phaseFileURL)
    }
}
