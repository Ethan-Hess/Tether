import Foundation

/// One line of the host's process list.
public struct ProcessEntry: Hashable, Sendable {
    public let pid: Int32
    public let command: String
}

public enum ProcessList {
    /// The host's processes (`ps -axo pid=,command=`). The command lines are only pattern-matched,
    /// never stored or logged: they can contain paths and arguments.
    public static func snapshot() -> [ProcessEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        process.environment = ["PATH": "/usr/bin:/bin"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile() // drain before waiting
        process.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

    public static func parse(_ output: String) -> [ProcessEntry] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.drop(while: { $0 == " " })
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { return nil }
            return ProcessEntry(pid: pid, command: String(trimmed[trimmed.index(after: space)...].drop(while: { $0 == " " })))
        }
    }
}

/// The Steam client's own process, as seen in the host's process list.
public enum SteamClientProcess {
    /// `steam.exe`, not `steamwebhelper.exe` or `steamerrorreporter64.exe`.
    public static func isClient(_ command: String) -> Bool {
        let lower = command.lowercased()
        var searchStart = lower.startIndex
        while let range = lower.range(of: "steam.exe", options: .literal, range: searchStart..<lower.endIndex) {
            let before = range.lowerBound > lower.startIndex ? lower[lower.index(before: range.lowerBound)] : nil
            let after = range.upperBound < lower.endIndex ? lower[range.upperBound] : nil
            let startsName = before.map { $0 == "\\" || $0 == "/" || $0 == " " || $0 == "\"" || $0 == "'" } ?? true
            let endsName = after.map { $0 == " " || $0 == "\"" || $0 == "'" } ?? true
            if startsName, endsName { return true }
            searchStart = range.upperBound
        }
        return false
    }

    public static func isRunning(in entries: [ProcessEntry]) -> Bool {
        entries.contains { isClient($0.command) }
    }

    public static func pids(in entries: [ProcessEntry]) -> [Int32] {
        entries.filter { isClient($0.command) }.map(\.pid)
    }
}

/// Steam's own record of which games are running, from `logs/gameprocess_log.txt` in the
/// bottle's Steam folder. It is keyed by Steam app ID and belongs to one bottle, so it needs no
/// guessing from process names and can't confuse two bottles that have the same game.
///
/// Steam writes lines such as:
/// ```
/// AppID 3480990 adding PID 1516 as a tracked process "C:\...\game.exe"
/// AppID 3480990 no longer tracking PID 1516, exit code 0
/// Remove 3480990 from running list
/// Client version: 1792618285        (written when Steam starts)
/// ```
/// The PIDs are Wine's Windows PIDs, not host PIDs.
public enum SteamGameProcessLog {
    /// Only the end of the file is read.
    public static let maxReadBytes = 128 * 1024

    public static func url(for bottle: Bottle) -> URL {
        bottle.driveC.appendingPathComponent(SteamLibrary.defaultRootInBottle + "/logs/gameprocess_log.txt")
    }

    /// Current size of the log, to remember where a launch began.
    public static func size(for bottle: Bottle) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url(for: bottle).path))?[.size] as? UInt64) ?? 0
    }

    /// Windows PIDs Steam is tracking, per app ID, in the current Steam session (after the last
    /// "Client version" line, since a restart forgets every running game). With `sinceOffset`,
    /// only what was written after that point counts, so a game left over from before can't
    /// look like the one just launched.
    public static func tracked(for bottle: Bottle, sinceOffset: UInt64? = nil) -> [Int: Set<Int>] {
        Reader(bottle: bottle, startingAt: sinceOffset).tracked
    }

    /// Follows the log as it grows, parsing only the bytes written since the last look, so a
    /// look costs about as much as what Steam just wrote, however large the file has become.
    public struct Reader: Sendable {
        public private(set) var tracked: [Int: Set<Int>] = [:]
        private var offset: UInt64 = 0
        /// Bytes after the last newline read so far (a line Steam was still writing).
        private var carry = Data()
        /// Set when starting in the middle of the file, so the first, partial line is dropped.
        private var dropFirstLine = false

        /// Starts at `startingAt`, or, when nil, at the end of the log's last `maxReadBytes`.
        public init(bottle: Bottle, startingAt: UInt64? = nil) {
            let size = SteamGameProcessLog.size(for: bottle)
            if let startingAt, startingAt <= size {
                offset = startingAt
            } else {
                offset = size > UInt64(SteamGameProcessLog.maxReadBytes) ? size - UInt64(SteamGameProcessLog.maxReadBytes) : 0
                dropFirstLine = offset > 0
            }
            advance(bottle)
        }

        /// Reads whatever was appended since the last call. A log that shrank (replaced) is read afresh.
        public mutating func advance(_ bottle: Bottle) {
            guard let handle = try? FileHandle(forReadingFrom: SteamGameProcessLog.url(for: bottle)) else { return }
            defer { try? handle.close() }
            guard let end = try? handle.seekToEnd() else { return }
            if end < offset {
                offset = 0
                carry = Data()
                tracked = [:]
                dropFirstLine = false
            }
            guard end > offset else { return }
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.read(upToCount: Int(end - offset)), !data.isEmpty else { return }
            offset += UInt64(data.count)

            var bytes = carry + data
            // Only whole lines are parsed; the rest waits for the next read.
            guard let lastNewline = bytes.lastIndex(of: 0x0A) else { carry = bytes; return }
            carry = Data(bytes[bytes.index(after: lastNewline)...])
            bytes = Data(bytes[...lastNewline])
            if dropFirstLine {
                dropFirstLine = false
                guard let firstNewline = bytes.firstIndex(of: 0x0A) else { return }
                bytes = Data(bytes[bytes.index(after: firstNewline)...])
            }
            SteamGameProcessLog.parse(String(decoding: bytes, as: UTF8.self), into: &tracked)
        }
    }

    public static func parse(_ text: String) -> [Int: Set<Int>] {
        var tracked: [Int: Set<Int>] = [:]
        parse(text, into: &tracked)
        return tracked
    }

    static func parse(_ text: String, into tracked: inout [Int: Set<Int>]) {
        // Steam's logs use Windows line endings; Swift sees "\r\n" as one character, so split on
        // anything that is a newline rather than on "\n".
        for line in text.split(whereSeparator: \.isNewline) {
            if line.contains("Client version:") { tracked = [:]; continue }
            let words = line.split(separator: " ")
            func number(after word: String) -> Int? {
                guard let i = words.firstIndex(of: Substring(word)), i + 1 < words.count else { return nil }
                return Int(words[i + 1].trimmingCharacters(in: CharacterSet(charactersIn: ",")))
            }
            if line.contains(" adding PID "), let app = number(after: "AppID"), let pid = number(after: "PID") {
                tracked[app, default: []].insert(pid)
            } else if line.contains(" no longer tracking PID "), let app = number(after: "AppID"), let pid = number(after: "PID") {
                tracked[app]?.remove(pid)
                if tracked[app]?.isEmpty == true { tracked[app] = nil }
            } else if line.contains(" from running list"), let i = words.firstIndex(of: "Remove"), i + 1 < words.count, let app = Int(words[i + 1]) {
                tracked[app] = nil
            }
        }
    }
}

public enum GamePhase: Equatable, Sendable {
    case idle
    /// Asked Steam to start the game; its process hasn't appeared yet.
    case launching
    case running
}

/// What a game launch is doing, decided from successive looks at the process list.
///
/// Launching ends when the game's process appears (running), when Steam goes away before it
/// does, or after a long wait. Running ends once the game's processes have been gone for two
/// looks in a row, so a launcher handing over to the real game isn't mistaken for a quit.
public struct GameLaunchTracker: Sendable {
    public static let launchTimeout: TimeInterval = 180
    /// How long Steam may be absent from the process list before the launch is given up on.
    public static let steamGrace: TimeInterval = 20

    public enum Failure: Equatable, Sendable {
        case steamClosed
        case timedOut
    }

    public private(set) var phase: GamePhase = .idle
    private var startedAt = Date()
    private var missedScans = 0

    public init() {}

    public mutating func begin(now: Date = Date()) {
        phase = .launching
        startedAt = now
        missedScans = 0
    }

    /// For a game that was already running when Tether looked.
    public mutating func adoptRunning() {
        phase = .running
        missedScans = 0
    }

    public mutating func cancel() { phase = .idle }

    /// While running, how often to double-check that Steam is still there. File events and a
    /// process-exit watch do the real work; this only catches anything they miss.
    public static let heartbeat: TimeInterval = 30

    /// Whether the next look needs to know if the Steam client is alive. That costs a little, so
    /// it's only asked when the answer matters: before giving up on a launch, and while running
    /// (a log left by a Steam that crashed would otherwise read as a running game).
    public func wantsSteamLiveness(gameRunning: Bool, now: Date = Date()) -> Bool {
        switch phase {
        case .idle: return false
        case .running: return true
        case .launching: return !gameRunning && now.timeIntervalSince(startedAt) > Self.steamGrace
        }
    }

    /// Seconds until this tracker needs a look even if nothing happens, or nil when idle.
    public func nextCheck(now: Date = Date()) -> TimeInterval? {
        switch phase {
        case .idle: return nil
        case .running: return Self.heartbeat
        case .launching:
            let elapsed = now.timeIntervalSince(startedAt)
            let deadline = elapsed < Self.steamGrace + 0.5 ? Self.steamGrace + 0.5 : Self.launchTimeout + 0.5
            return max(0.5, deadline - elapsed)
        }
    }

    /// Feed one look at the process list. Returns a failure when a launch is abandoned.
    @discardableResult
    public mutating func update(gameRunning: Bool, steamRunning: Bool, now: Date = Date()) -> Failure? {
        switch phase {
        case .idle:
            return nil
        case .launching:
            if gameRunning {
                phase = .running
                missedScans = 0
                return nil
            }
            let waited = now.timeIntervalSince(startedAt)
            if waited > Self.launchTimeout { phase = .idle; return .timedOut }
            if waited > Self.steamGrace, !steamRunning { phase = .idle; return .steamClosed }
            return nil
        case .running:
            if gameRunning { missedScans = 0; return nil }
            missedScans += 1
            if missedScans >= 2 { phase = .idle }
            return nil
        }
    }
}
