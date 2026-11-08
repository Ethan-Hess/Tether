import Foundation

public enum TetherDataError: Error, LocalizedError, Equatable {
    case unsafeRoot(String)

    public var errorDescription: String? {
        switch self {
        case .unsafeRoot(let p): return "Refusing to remove data under \(p): it doesn't look like a Tether data folder."
        }
    }
}

public enum TetherDataCategory: String, CaseIterable, Identifiable, Sendable {
    /// Wine prefixes: installed games, saves and Steam itself.
    case bottles
    /// Installed Wine runtimes and imported components (GPTK).
    case runtimes
    /// Downloaded artwork. Re-created on demand.
    case cache
    /// App settings and your own game profiles.
    case settings

    public var id: String { rawValue }
}

/// What Tether keeps on disk, and removing it. Only known folders and files directly inside the
/// data root are ever touched, never the root itself unless it ends up empty (a custom
/// `TETHER_HOME` can hold other things), and links are removed rather than followed.
public enum TetherData {
    public static func locations(for category: TetherDataCategory, paths: TetherPaths) -> [URL] {
        switch category {
        case .bottles: return [paths.bottles]
        case .runtimes: return [paths.runtimes, paths.userComponents]
        case .cache: return [paths.cache]
        case .settings: return [paths.settings, paths.profiles]
        }
    }

    /// Bytes on disk per category.
    public static func summary(paths: TetherPaths) -> [TetherDataCategory: Int64] {
        var result: [TetherDataCategory: Int64] = [:]
        for category in TetherDataCategory.allCases {
            result[category] = locations(for: category, paths: paths).reduce(0) { $0 + DiskUsage.size(of: $1) }
        }
        return result
    }

    /// Removes the chosen categories and returns what was deleted.
    @discardableResult
    public static func remove(_ categories: Set<TetherDataCategory>, paths: TetherPaths) throws -> [URL] {
        let fm = FileManager.default
        let root = paths.root.standardizedFileURL
        try checkRoot(root)

        var removed: [URL] = []
        for category in TetherDataCategory.allCases where categories.contains(category) {
            for location in locations(for: category, paths: paths) {
                let target = location.standardizedFileURL
                // Belt and braces: each target must sit directly inside the root.
                guard target.deletingLastPathComponent().path == root.path, target.path != root.path else { continue }
                guard (try? fm.attributesOfItem(atPath: target.path)) != nil else { continue } // nothing there
                try fm.removeItem(at: target) // a symbolic link is removed, not followed
                removed.append(target)
            }
        }
        // Leave the root alone if anything else is in it.
        let leftovers = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        if leftovers.allSatisfy({ $0 == ".DS_Store" }), fm.fileExists(atPath: root.path) {
            try? fm.removeItem(at: root)
        }
        return removed
    }

    /// The root must be a real folder well below the top of the disk, and not the home folder.
    static func checkRoot(_ root: URL) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if root.pathComponents.count < 3 || root.path == home || root.path == "/Users" {
            throw TetherDataError.unsafeRoot(root.path)
        }
    }
}
