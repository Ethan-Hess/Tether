import Foundation

/// Per-game tuning. Profiles are declarative data (JSON). They may only express things
/// Tether's launch policy allows: backend choice, sync mode, Windows version,
/// translation-surface DLL overrides, and non-protected environment variables.
public struct GameProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Executable file names (case-insensitive) used for automatic matching.
    public var executables: [String]
    /// Backends to try in order. Unavailable ones are skipped.
    public var backendPreference: [GraphicsBackendID]
    public var sync: SyncMode?
    public var windowsVersion: WindowsVersion?
    public var environment: [String: String]
    public var dllOverrides: [DLLOverride]
    /// Free-form notes shown in the UI (known issues, anti-cheat status, etc.).
    public var notes: String?

    public init(
        id: String,
        name: String,
        executables: [String] = [],
        backendPreference: [GraphicsBackendID] = [],
        sync: SyncMode? = nil,
        windowsVersion: WindowsVersion? = nil,
        environment: [String: String] = [:],
        dllOverrides: [DLLOverride] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.executables = executables
        self.backendPreference = backendPreference
        self.sync = sync
        self.windowsVersion = windowsVersion
        self.environment = environment
        self.dllOverrides = dllOverrides
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        executables = try c.decodeIfPresent([String].self, forKey: .executables) ?? []
        backendPreference = try c.decodeIfPresent([GraphicsBackendID].self, forKey: .backendPreference) ?? []
        sync = try c.decodeIfPresent(SyncMode.self, forKey: .sync)
        windowsVersion = try c.decodeIfPresent(WindowsVersion.self, forKey: .windowsVersion)
        environment = try c.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        dllOverrides = try c.decodeIfPresent([DLLOverride].self, forKey: .dllOverrides) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }
}

/// Built-in profiles (bundled JSON) merged with user profiles from `TetherPaths.profiles`.
/// A user profile with the same id replaces the built-in one.
public struct ProfileLibrary: Sendable {
    public let profiles: [GameProfile]

    public init(profiles: [GameProfile]) {
        self.profiles = profiles
    }

    public static func load(paths: TetherPaths = .default) -> ProfileLibrary {
        var byID: [String: GameProfile] = [:]
        let builtinDir = Bundle.module.url(forResource: "Profiles", withExtension: nil)
        for dir in [builtinDir, paths.profiles].compactMap({ $0 }) {
            for profile in loadDirectory(dir) { byID[profile.id] = profile }
        }
        return ProfileLibrary(profiles: byID.values.sorted { $0.name < $1.name })
    }

    static func loadDirectory(_ dir: URL) -> [GameProfile] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            do {
                return try JSONDecoder().decode(GameProfile.self, from: Data(contentsOf: url))
            } catch {
                TetherLog.profiles.error("Skipping profile \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    public func profile(id: String) -> GameProfile? {
        profiles.first { $0.id == id }
    }

    /// Matches by executable file name, e.g. `C:\Program Files (x86)\Overwatch\_retail_\Overwatch.exe`.
    public func match(executable: String) -> GameProfile? {
        let name = executable
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .last.map(String.init)?.lowercased() ?? ""
        return profiles.first { $0.executables.contains { $0.lowercased() == name } }
    }
}
