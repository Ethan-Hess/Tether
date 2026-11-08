import Foundation

/// Reads a bottle's `logs/wine.log` as separate launches.
///
/// Each launch that logs starts with a marker line (written by `Launcher.launch`). Output from
/// before the first marker, for example from an older version, is shown as one "earlier" session.
public enum LaunchLog {
    public static let markerPrefix = "=== tether launch "
    public static let markerSuffix = " ==="
    /// Only the end of a very large log is read, so the viewer never loads a huge file.
    public static let maxReadBytes = 2 * 1024 * 1024

    public struct Session: Identifiable, Hashable, Sendable {
        public let id: Int
        public let start: Date?
        public let executable: String
        public let text: String
    }

    private static func logURL(_ bottle: Bottle) -> URL { bottle.logsURL.appendingPathComponent("wine.log") }

    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    public static func markerLine(date: Date = Date(), executable: String) -> String {
        let name = executable.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? executable
        // One line only: a name with a newline could forge a marker.
        let safe = name.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        return "\(markerPrefix)\(iso(date)) \(safe)\(markerSuffix)\n"
    }

    public static func appendMarker(to bottle: Bottle, executable: String, date: Date = Date()) {
        guard let handle = try? FileHandle.forWritingAtEnd(creatingIfNeeded: logURL(bottle)) else { return }
        defer { try? handle.close() }
        try? handle.write(contentsOf: Data(markerLine(date: date, executable: executable).utf8))
    }

    /// Sessions, oldest first.
    public static func sessions(for bottle: Bottle) -> [Session] {
        parse(readTail(logURL(bottle)))
    }

    public static func parse(_ text: String) -> [Session] {
        var sessions: [Session] = []
        var start: Date?
        var executable = "Earlier output"
        var lines: [Substring] = []
        var open = false

        func flush() {
            let body = lines.joined(separator: "\n")
            if open || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sessions.append(Session(id: sessions.count, start: start, executable: executable, text: body))
            }
            lines = []
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(markerPrefix), line.hasSuffix(markerSuffix) {
                flush()
                let inner = line.dropFirst(markerPrefix.count).dropLast(markerSuffix.count)
                let parts = inner.split(separator: " ", maxSplits: 1).map(String.init)
                start = parts.first.flatMap { ISO8601DateFormatter().date(from: $0) }
                executable = parts.count > 1 ? parts[1] : "?"
                open = true
            } else {
                lines.append(line)
            }
        }
        flush()
        // Drop the empty tail a trailing newline leaves.
        return sessions.map { s in
            Session(id: s.id, start: s.start, executable: s.executable, text: s.text.trimmingCharacters(in: .newlines))
        }
    }

    public static func clear(_ bottle: Bottle) throws {
        let url = logURL(bottle)
        if FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
    }

    private static func readTail(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return "" }
        let offset = size > UInt64(maxReadBytes) ? size - UInt64(maxReadBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return "" }
        var text = String(decoding: data, as: UTF8.self)
        if offset > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...]) // drop the partial first line
        }
        return text
    }
}
