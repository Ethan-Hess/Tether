import Foundation

/// Assembles the complete environment for a Wine launch.
///
/// The environment is built from scratch (only a small allowlist is inherited from the host)
/// so launches are reproducible and nothing from the user's shell, such as `DYLD_*`
/// variables, leaks into the game process.
///
/// Precedence, lowest to highest:
/// inherited host vars → Tether core vars → backend → sync → profile env → bottle env.
/// Protected keys (see `protectedKeys`) are owned by Tether and can't be overridden by profiles or bottles.
public struct LaunchEnvironment: Sendable {
    public static let inheritedKeys: Set<String> = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "SHELL"]

    /// Keys that profiles/bottles may not set. These are either Tether-owned or
    /// code-injection vectors (ADR 0003).
    public static func isProtected(_ key: String) -> Bool {
        let owned: Set<String> = ["WINEPREFIX", "WINEDLLOVERRIDES", "WINEDLLPATH", "WINESERVER", "WINELOADER", "PATH"]
        return owned.contains(key) || key.hasPrefix("DYLD_")
    }

    public var variables: [String: String]
    public var backend: any GraphicsBackend
    public var profile: GameProfile?
    /// Overrides or env keys dropped by policy, for display in UI/CLI.
    public var rejectedOverrides: [DLLOverride]
    public var rejectedEnvironmentKeys: [String]

    public struct Options: Sendable {
        /// Enables Wine debug output and backend logging. Off by default because logging
        /// has a measurable cost in hot paths.
        public var debug: Bool
        public var baseEnvironment: [String: String]

        public init(debug: Bool = false, baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
            self.debug = debug
            self.baseEnvironment = baseEnvironment
        }
    }

    public init(
        bottle: Bottle,
        runtime: WineRuntime,
        backend: any GraphicsBackend,
        profile: GameProfile?,
        paths: TetherPaths,
        options: Options = Options()
    ) {
        self.backend = backend
        self.profile = profile

        var env: [String: String] = options.baseEnvironment.filter { Self.inheritedKeys.contains($0.key) }

        // Core
        env["PATH"] = [runtime.root.appendingPathComponent("bin").path, "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .joined(separator: ":")
        env["WINEPREFIX"] = bottle.prefixURL.path
        env["WINEDEBUG"] = options.debug ? "fixme-all,err+all" : "-all"
        if let extra = backend.builtinSearchPath(runtime: runtime, paths: paths) {
            env["WINEDLLPATH"] = extra.path
        }

        // Backend
        let backendOptions = BackendOptions(showHUD: bottle.config.showPerformanceHUD, cacheDirectory: bottle.cacheURL)
        env.merge(backend.environment(options: backendOptions)) { _, new in new }

        // Sync: bottle > profile > msync. Degrade to esync if the runtime lacks msync.
        let sync = bottle.config.sync ?? profile?.sync ?? .msync
        switch sync {
        case .msync where runtime.supports(feature: "msync"):
            env["WINEMSYNC"] = "1"
        case .msync, .esync:
            env["WINEESYNC"] = "1"
        case .none:
            break
        }

        // DLL overrides: backend's own + policy-filtered profile overrides.
        let filtered = OverridePolicy.filter(profile?.dllOverrides ?? [])
        rejectedOverrides = filtered.rejected
        var overrides = backend.dllOverrides + filtered.allowed
        // Host-side: don't let Wine generate macOS menu/desktop entries on every launch.
        overrides.append(DLLOverride("winemenubuilder.exe", .disabled))
        env["WINEDLLOVERRIDES"] = DLLOverride.render(overrides)

        // Profile then bottle env, minus protected keys.
        var rejectedKeys: [String] = []
        for layer in [profile?.environment ?? [:], bottle.config.environment] {
            for (key, value) in layer {
                if Self.isProtected(key) { rejectedKeys.append(key) } else { env[key] = value }
            }
        }
        rejectedEnvironmentKeys = rejectedKeys.sorted()

        variables = env
    }
}
