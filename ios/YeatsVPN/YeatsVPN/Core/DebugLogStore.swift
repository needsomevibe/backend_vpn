import Foundation
import os.log

@MainActor
final class DebugLogStore: ObservableObject {
    @Published private(set) var entries: [DebugLogEntry] = []

    private let logger = Logger(subsystem: "uz.yeats.vpn", category: "App")
    private var importedExtensionLines = Set<String>()
    private var didLogSharedDiagnosticsStatus = false

    func info(_ message: String) {
        append(level: "info", message: message)
        logger.info("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        append(level: "error", message: message)
        logger.error("\(message, privacy: .public)")
    }

    func clear() {
        entries.removeAll()
        importedExtensionLines.removeAll()
        didLogSharedDiagnosticsStatus = false
        SharedDiagnostics.clear()
    }

    func importExtensionLogs(includeStatus: Bool = false) {
        if includeStatus || !didLogSharedDiagnosticsStatus {
            didLogSharedDiagnosticsStatus = true
            append(level: "diagnostic", message: SharedDiagnostics.statusMessage)
        }

        for line in SharedDiagnostics.readLines() where !importedExtensionLines.contains(line) {
            importedExtensionLines.insert(line)
            append(level: "extension", message: line)
        }
    }

    private func append(level: String, message: String) {
        entries.append(DebugLogEntry(date: Date(), level: level, message: message))
        if entries.count > 80 {
            entries.removeFirst(entries.count - 80)
        }
    }
}

struct DebugLogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let level: String
    let message: String

    var display: String {
        let time = date.formatted(.dateTime.hour().minute().second())
        return "\(time) [\(level)] \(message)"
    }
}
