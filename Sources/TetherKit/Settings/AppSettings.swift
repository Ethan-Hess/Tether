import Foundation

/// App-wide preferences. These only choose defaults for new bottles and the app's own behaviour;
/// they never change how a launch is assembled (launch policy, ADR 0003).
public struct AppSettings: Codable, Equatable, Sendable {
    public var defaultBackend: GraphicsBackendID?
    public var defaultWindowsVersion: WindowsVersion
    public var defaultShowPerformanceHUD: Bool
    /// Pre-selects "Log Wine output" for runs started from the app.
    public var debugLoggingByDefault: Bool

    public init(
        defaultBackend: GraphicsBackendID? = nil,
        defaultWindowsVersion: WindowsVersion = .win10,
        defaultShowPerformanceHUD: Bool = false,
        debugLoggingByDefault: Bool = false
    ) {
        self.defaultBackend = defaultBackend
        self.defaultWindowsVersion = defaultWindowsVersion
        self.defaultShowPerformanceHUD = defaultShowPerformanceHUD
        self.debugLoggingByDefault = debugLoggingByDefault
    }

    private enum CodingKeys: String, CodingKey {
        case defaultBackend, defaultWindowsVersion, defaultShowPerformanceHUD, debugLoggingByDefault
    }

    /// Each field falls back to its default on its own, so a value written by a newer version
    /// (an unknown backend, say) or a missing key never discards the rest.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultBackend = try? c.decodeIfPresent(GraphicsBackendID.self, forKey: .defaultBackend)
        defaultWindowsVersion = (try? c.decodeIfPresent(WindowsVersion.self, forKey: .defaultWindowsVersion)) ?? .win10
        defaultShowPerformanceHUD = (try? c.decodeIfPresent(Bool.self, forKey: .defaultShowPerformanceHUD)) ?? false
        debugLoggingByDefault = (try? c.decodeIfPresent(Bool.self, forKey: .debugLoggingByDefault)) ?? false
    }

    /// The config a new bottle starts with.
    public func newBottleConfig(profileID: String? = nil) -> BottleConfig {
        BottleConfig(
            backend: defaultBackend,
            profileID: profileID,
            windowsVersion: defaultWindowsVersion,
            showPerformanceHUD: defaultShowPerformanceHUD
        )
    }
}

public struct SettingsStore: Sendable {
    public let paths: TetherPaths

    public init(paths: TetherPaths = .default) {
        self.paths = paths
    }

    /// Defaults when the file is missing or unreadable.
    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: paths.settings),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: paths.settings, options: .atomic)
    }
}
