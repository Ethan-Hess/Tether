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
public struct BottleStore: Sendable {
    public let paths: TetherPaths

    public init(paths: TetherPaths = .default) {
        self.paths = paths
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
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.bottles.path) else { return [] }
        let entries = try fm.contentsOfDirectory(at: paths.bottles, includingPropertiesForKeys: nil)
        return entries
            .compactMap { try? load(name: $0.lastPathComponent) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func load(name: String) throws -> Bottle {
        try Self.validate(name: name)
        let root = url(for: name)
        let configURL = root.appendingPathComponent("bottle.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw BottleStoreError.notFound(name)
        }
        let config = try Self.decoder.decode(BottleConfig.self, from: Data(contentsOf: configURL))
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

    public func delete(name: String) throws {
        try Self.validate(name: name)
        let root = url(for: name)
        guard FileManager.default.fileExists(atPath: root.path) else { throw BottleStoreError.notFound(name) }
        try FileManager.default.removeItem(at: root)
    }
}
