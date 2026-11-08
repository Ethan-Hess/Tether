import Foundation

/// Filesystem layout for everything Tether owns.
///
/// Default root: `~/Library/Application Support/Tether`. Override with the
/// `TETHER_HOME` environment variable (used by tests and for portable installs).
public struct TetherPaths: Sendable, Hashable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var `default`: TetherPaths {
        if let override = ProcessInfo.processInfo.environment["TETHER_HOME"], !override.isEmpty {
            return TetherPaths(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return TetherPaths(root: appSupport.appendingPathComponent("Tether", isDirectory: true))
    }

    /// One directory per bottle: `Bottles/<name>/{bottle.json,prefix/,cache/,logs/}`
    public var bottles: URL { root.appendingPathComponent("Bottles", isDirectory: true) }

    /// One directory per runtime build: `Runtimes/<version>/{runtime.json,bin/,lib/,backends/}`
    public var runtimes: URL { root.appendingPathComponent("Runtimes", isDirectory: true) }

    /// User-supplied components that Tether cannot redistribute (e.g. Apple GPTK / D3DMetal).
    public var userComponents: URL { root.appendingPathComponent("UserComponents", isDirectory: true) }

    /// User-authored game profiles; these override built-ins with the same id.
    public var profiles: URL { root.appendingPathComponent("Profiles", isDirectory: true) }

    /// Re-creatable downloads such as Steam artwork. Safe to delete.
    public var cache: URL { root.appendingPathComponent("Cache", isDirectory: true) }

    /// Global settings file.
    public var settings: URL { root.appendingPathComponent("settings.json") }
}
