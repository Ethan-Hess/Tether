import Foundation

/// Windows version reported by the prefix. Raw values match `winecfg -v`.
public enum WindowsVersion: String, Codable, CaseIterable, Sendable {
    case win7, win8, win81, win10, win11
}

/// Wine synchronization primitive implementation.
///
/// `msync` (Mach semaphores) is the lowest-overhead option on macOS and the default.
/// It requires a Wine build carrying the msync patches (see `runtime/patches/wine`).
public enum SyncMode: String, Codable, CaseIterable, Sendable {
    case msync, esync, none
}

/// Persisted configuration for a bottle, stored as `bottle.json`.
public struct BottleConfig: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Runtime version to launch with. `nil` means "latest installed".
    public var runtimeVersion: String?
    /// Explicit user choice of graphics backend. `nil` means "let the profile/default decide".
    public var backend: GraphicsBackendID?
    /// Game profile id applied to every launch in this bottle, if any.
    public var profileID: String?
    public var windowsVersion: WindowsVersion
    /// `nil` means "use profile or default (msync)".
    public var sync: SyncMode?
    /// Extra environment variables. Highest precedence, applied last.
    public var environment: [String: String]
    /// Show the backend-native performance HUD (DXVK_HUD / Metal HUD).
    public var showPerformanceHUD: Bool
    public var createdAt: Date

    public init(
        runtimeVersion: String? = nil,
        backend: GraphicsBackendID? = nil,
        profileID: String? = nil,
        windowsVersion: WindowsVersion = .win10,
        sync: SyncMode? = nil,
        environment: [String: String] = [:],
        showPerformanceHUD: Bool = false,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runtimeVersion = runtimeVersion
        self.backend = backend
        self.profileID = profileID
        self.windowsVersion = windowsVersion
        self.sync = sync
        self.environment = environment
        self.showPerformanceHUD = showPerformanceHUD
        self.createdAt = createdAt
    }
}

/// A bottle is an isolated Wine prefix plus its Tether configuration.
///
/// One game (or one launcher, e.g. Steam) per bottle is recommended: it keeps the
/// prefix clean, which is both faster and the least surprising environment for anti-cheat.
public struct Bottle: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    /// `Bottles/<name>`
    public let root: URL
    public var config: BottleConfig

    public init(name: String, root: URL, config: BottleConfig) {
        self.name = name
        self.root = root
        self.config = config
    }

    public var configURL: URL { root.appendingPathComponent("bottle.json") }
    /// The actual `WINEPREFIX`.
    public var prefixURL: URL { root.appendingPathComponent("prefix", isDirectory: true) }
    /// Shader / pipeline caches, persisted across launches so stutter only happens once.
    public var cacheURL: URL { root.appendingPathComponent("cache", isDirectory: true) }
    public var logsURL: URL { root.appendingPathComponent("logs", isDirectory: true) }

    public var driveC: URL { prefixURL.appendingPathComponent("drive_c", isDirectory: true) }
    public var system32: URL { driveC.appendingPathComponent("windows/system32", isDirectory: true) }
    public var syswow64: URL { driveC.appendingPathComponent("windows/syswow64", isDirectory: true) }
}
