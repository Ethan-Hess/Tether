import Foundation

public enum BottleStoreError: Error, LocalizedError, Equatable {
    case invalidName(String)
    case alreadyExists(String)
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let n): return "Invalid bottle name '\(n)'. Use letters, numbers, spaces, '-', '_' or '.'."
        case .alreadyExists(let n): return "A bottle named '\(n)' already exists."
        case .notFound(let n): return "No bottle named '\(n)'."
        }
    }
}

/// CRUD for bottles on disk. Does not run Wine; see `Launcher.initializePrefix` for that.
/// A bottle folder that exists but can't be opened (damaged or from a newer Tether).
public struct BottleProblem: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let message: String
}

public struct BottleStore: Sendable {
    public let paths: TetherPaths
    public let migrator: BottleMigrator

    public init(paths: TetherPaths = .default, migrator: BottleMigrator = .standard) {
        self.paths = paths
        self.migrator = migrator
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func validate(name: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        guard !name.isEmpty,
              name.count <= 64,
              !name.hasPrefix("."),
              name.unicodeScalars.allSatisfy(allowed.contains)
        else { throw BottleStoreError.invalidName(name) }
    }

    public func url(for name: String) -> URL {
        paths.bottles.appendingPathComponent(name, isDirectory: true)
    }

    public func list() throws -> [Bottle] {
        try listWithProblems().bottles
    }

    /// Bottles that open, plus folders that look like bottles but can't be opened. Nothing is
    /// hidden: the caller can show the problems instead of a bottle silently going missing.
    public func listWithProblems() throws -> (bottles: [Bottle], problems: [BottleProblem]) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.bottles.path) else { return ([], []) }
        let entries = try fm.contentsOfDirectory(at: paths.bottles, includingPropertiesForKeys: nil)
        var bottles: [Bottle] = []
        var problems: [BottleProblem] = []
        for entry in entries {
            let name = entry.lastPathComponent
            guard fm.fileExists(atPath: entry.appendingPathComponent("bottle.json").path) else { continue }
            do {
                bottles.append(try load(name: name))
            } catch {
                problems.append(BottleProblem(name: name, message: error.localizedDescription))
            }
        }
        bottles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        problems.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (bottles, problems)
    }

    public func load(name: String) throws -> Bottle {
        try Self.validate(name: name)
        let root = url(for: name)
        let configURL = root.appendingPathComponent("bottle.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw BottleStoreError.notFound(name)
        }
        var data = try Data(contentsOf: configURL)
        if let migrated = try migrator.migrate(data) {
            // Keep the original next to the upgraded file, then replace it atomically.
            let backup = root.appendingPathComponent("bottle.json.v\(migrated.from).bak")
            if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup) }
            try migrated.data.write(to: configURL, options: .atomic)
            data = migrated.data
        }
        let config = try Self.decoder.decode(BottleConfig.self, from: data)
        return Bottle(name: name, root: root, config: config)
    }

    /// Creates the bottle directory structure and `bottle.json`.
    /// The Wine prefix itself is populated on first launch (`wineboot --init`).
    @discardableResult
    public func create(name: String, config: BottleConfig = BottleConfig()) throws -> Bottle {
        try Self.validate(name: name)
        let root = url(for: name)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: root.path) else { throw BottleStoreError.alreadyExists(name) }

        let bottle = Bottle(name: name, root: root, config: config)
        for dir in [bottle.prefixURL, bottle.cacheURL, bottle.logsURL] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try save(bottle)
        return bottle
    }

    public func save(_ bottle: Bottle) throws {
        let data = try Self.encoder.encode(bottle.config)
        try data.write(to: bottle.configURL, options: .atomic)
    }

    /// Renames a bottle's directory. The Wine prefix keeps working: Wine records no absolute
    /// path to itself that matters for launching, and `WINEPREFIX` is set from the new location.
    @discardableResult
    public func rename(from old: String, to new: String) throws -> Bottle {
        try Self.validate(name: new)
        let source = try load(name: old)
        let destination = url(for: new)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw BottleStoreError.alreadyExists(new) }
        try FileManager.default.moveItem(at: source.root, to: destination)
        return try load(name: new)
    }

    /// Copies a whole bottle (prefix, caches and config) under a new name.
    @discardableResult
    public func duplicate(name: String, as copy: String) throws -> Bottle {
        try Self.validate(name: copy)
        let source = try load(name: name)
        let destination = url(for: copy)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw BottleStoreError.alreadyExists(copy) }
        try FileManager.default.copyItem(at: source.root, to: destination)
        return try load(name: copy)
    }

    public func exists(name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    public func delete(name: String) throws {
        try Self.validate(name: name)
        let root = url(for: name)
        guard FileManager.default.fileExists(atPath: root.path) else { throw BottleStoreError.notFound(name) }
        try FileManager.default.removeItem(at: root)
    }
}
