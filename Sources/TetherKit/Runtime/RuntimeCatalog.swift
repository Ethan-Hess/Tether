import Foundation

/// A pinned, downloadable runtime build (ADR 0005: wrap a community arm64 + FEX build first).
///
/// The hash is pinned in Tether, so a changed or tampered download is rejected.
public struct RuntimeSource: Codable, Hashable, Sendable {
    /// Tether's own runtime version; becomes the directory name under `Runtimes/`.
    public var version: String
    public var wineVersion: String
    public var features: [String]
    public var components: [RuntimeManifest.Component]
    public var url: URL
    /// Lowercase hex SHA-256 of the archive.
    public var sha256: String
    public var size: Int64
    /// Leading path components to drop when unpacking (e.g. 1 for an archive with a `wine/` top directory).
    public var stripComponents: Int
    /// Minimum macOS ("26.4") needed to run this runtime, if any.
    public var minimumMacOS: String?

    public var manifest: RuntimeManifest {
        RuntimeManifest(version: version, wineVersion: wineVersion, features: features, components: components)
    }
}

public struct RuntimeCatalog: Codable, Sendable {
    public var runtimes: [RuntimeSource]

    public init(runtimes: [RuntimeSource]) {
        self.runtimes = runtimes
    }

    /// The catalog bundled with TetherKit.
    public static func bundled() -> RuntimeCatalog {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json", subdirectory: "Runtimes"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(RuntimeCatalog.self, from: data)
        else {
            TetherLog.runtime.error("runtime catalog missing or unreadable")
            return RuntimeCatalog(runtimes: [])
        }
        return catalog
    }

    /// The source for `version`, or the newest one when nil.
    public func source(version: String?) -> RuntimeSource? {
        if let version { return runtimes.first { $0.version == version } }
        return runtimes.max { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
    }
}
