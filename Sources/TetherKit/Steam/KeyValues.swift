import Foundation

public enum KeyValuesError: Error, Equatable, LocalizedError {
    case unexpectedEnd
    case unexpected(String, offset: Int)
    case tooDeep

    public var errorDescription: String? {
        switch self {
        case .unexpectedEnd: return "Unexpected end of file."
        case .unexpected(let what, let offset): return "Unexpected \(what) at byte \(offset)."
        case .tooDeep: return "Nesting is too deep."
        }
    }
}

/// Valve's text KeyValues format (`.vdf` / `.acf`), as used by Steam's `libraryfolders.vdf`
/// and `appmanifest_<appid>.acf`.
///
/// ```
/// "AppState"
/// {
///     "appid"  "730"
///     "name"   "Counter-Strike 2"
/// }
/// ```
/// Keys may repeat, so objects are ordered entry lists. Lookups are case-insensitive, as in Steam.
/// The input comes from files on disk that games and launchers write, so parsing is strict,
/// bounds-checked, and depth-limited rather than trusting the content.
public enum KeyValues: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let key: String
        public let value: KeyValues
    }

    case string(String)
    case object([Entry])

    static let maxDepth = 32

    public var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var entries: [Entry] {
        if case .object(let e) = self { return e }
        return []
    }

    /// First value for `key`, case-insensitive.
    public subscript(key: String) -> KeyValues? {
        entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    /// Parses a document. The result is always an `.object` of the top-level entries.
    public static func parse(_ text: String) throws -> KeyValues {
        var parser = Parser(bytes: Array(text.utf8))
        parser.skipBOM()
        return .object(try parser.parseEntries(depth: 0, closing: false))
    }

    private struct Parser {
        let bytes: [UInt8]
        var pos = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func skipBOM() {
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { pos = 3 }
        }

        mutating func skipTrivia() {
            while pos < bytes.count {
                let b = bytes[pos]
                if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
                    pos += 1
                } else if b == 0x2F, pos + 1 < bytes.count, bytes[pos + 1] == 0x2F {
                    while pos < bytes.count, bytes[pos] != 0x0A { pos += 1 }
                } else {
                    return
                }
            }
        }

        mutating func parseEntries(depth: Int, closing: Bool) throws -> [Entry] {
            guard depth <= KeyValues.maxDepth else { throw KeyValuesError.tooDeep }
            var entries: [Entry] = []
            while true {
                skipTrivia()
                guard pos < bytes.count else {
                    if closing { throw KeyValuesError.unexpectedEnd }
                    return entries
                }
                if bytes[pos] == UInt8(ascii: "}") {
                    guard closing else { throw KeyValuesError.unexpected("'}'", offset: pos) }
                    pos += 1
                    return entries
                }
                let key = try readToken()
                skipTrivia()
                guard pos < bytes.count else { throw KeyValuesError.unexpectedEnd }
                if bytes[pos] == UInt8(ascii: "{") {
                    pos += 1
                    entries.append(Entry(key: key, value: .object(try parseEntries(depth: depth + 1, closing: true))))
                } else {
                    entries.append(Entry(key: key, value: .string(try readToken())))
                }
            }
        }

        mutating func readToken() throws -> String {
            guard pos < bytes.count else { throw KeyValuesError.unexpectedEnd }
            let first = bytes[pos]
            if first == UInt8(ascii: "\"") { return try readQuoted() }
            if first == UInt8(ascii: "{") || first == UInt8(ascii: "}") {
                throw KeyValuesError.unexpected("'\(Character(UnicodeScalar(first)))'", offset: pos)
            }
            let start = pos
            while pos < bytes.count {
                let b = bytes[pos]
                if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == UInt8(ascii: "\"")
                    || b == UInt8(ascii: "{") || b == UInt8(ascii: "}") { break }
                pos += 1
            }
            return String(decoding: bytes[start..<pos], as: UTF8.self)
        }

        mutating func readQuoted() throws -> String {
            pos += 1 // opening quote
            var out: [UInt8] = []
            while pos < bytes.count {
                let b = bytes[pos]
                pos += 1
                if b == UInt8(ascii: "\"") { return String(decoding: out, as: UTF8.self) }
                if b == UInt8(ascii: "\\"), pos < bytes.count {
                    let next = bytes[pos]
                    pos += 1
                    switch next {
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "\\"): out.append(UInt8(ascii: "\\"))
                    case UInt8(ascii: "\""): out.append(UInt8(ascii: "\""))
                    default: out.append(b); out.append(next) // unknown escape: keep it literally
                    }
                } else {
                    out.append(b)
                }
            }
            throw KeyValuesError.unexpectedEnd
        }
    }
}
