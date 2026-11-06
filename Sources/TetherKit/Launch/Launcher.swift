import Foundation

public struct LaunchRequest: Sendable {
    public var bottle: Bottle
    /// A Windows path (`C:\...`) or a host path to a `.exe`.
    public var executable: String
    public var arguments: [String]
    /// Forces a profile; otherwise bottle's profile, then auto-match by executable name.
    public var profileID: String?
    public var debug: Bool

    public init(bottle: Bottle, executable: String, arguments: [String] = [], profileID: String? = nil, debug: Bool = false) {
        self.bottle = bottle
        self.executable = executable
        self.arguments = arguments
        self.profileID = profileID
        self.debug = debug
    }
}

/// Everything needed to start a process, computed without side effects.
public struct LaunchPlan: Sendable {
    public var bottle: Bottle
    public var runtime: WineRuntime
    public var environment: LaunchEnvironment
    public var executableURL: URL
    public var arguments: [String]
    public var workingDirectory: URL
    /// A backend the bottle explicitly asked for that this runtime can't honour because it
    /// manages graphics itself. Surfaced so the CLI/UI can say so instead of silently ignoring it.
    public var ignoredBackendChoice: GraphicsBackendID? = nil
}

/// Spawns Wine processes for a bottle.
///
/// Tether's host process is never inside the game's address space: it only sets up files
/// and environment, then `posix_spawn`s Wine (native arm64; FEX translates x86 code). After that,
/// the only interaction is waiting for exit or asking `wineserver` to shut down.
public struct Launcher: Sendable {
    public let paths: TetherPaths
    public let runtimes: RuntimeStore
    public let profiles: ProfileLibrary
    public let installer: BackendInstaller

    public init(paths: TetherPaths = .default, profiles: ProfileLibrary? = nil) {
        self.paths = paths
        self.runtimes = RuntimeStore(paths: paths)
        self.profiles = profiles ?? ProfileLibrary.load(paths: paths)
        self.installer = BackendInstaller(paths: paths)
    }

    public func resolveProfile(for request: LaunchRequest) -> GameProfile? {
        if let id = request.profileID ?? request.bottle.config.profileID {
            return profiles.profile(id: id)
        }
        return profiles.match(executable: request.executable)
    }

    public func plan(_ request: LaunchRequest) throws -> LaunchPlan {
        let runtime = try runtimes.resolve(version: request.bottle.config.runtimeVersion)
        let profile = resolveProfile(for: request)
        let backend = GraphicsBackends.resolve(
            bottleChoice: request.bottle.config.backend,
            profile: profile,
            runtime: runtime,
            paths: paths
        )
        let env = LaunchEnvironment(
            bottle: request.bottle,
            runtime: runtime,
            backend: backend,
            profile: profile,
            paths: paths,
            options: .init(debug: request.debug)
        )

        let hostExe = URL(fileURLWithPath: request.executable)
        let workingDirectory = FileManager.default.fileExists(atPath: hostExe.path)
            ? hostExe.deletingLastPathComponent()
            : request.bottle.driveC

        return LaunchPlan(
            bottle: request.bottle,
            runtime: runtime,
            environment: env,
            executableURL: runtime.wineBinary,
            arguments: [request.executable] + request.arguments,
            workingDirectory: workingDirectory,
            ignoredBackendChoice: {
                guard let choice = request.bottle.config.backend, choice != backend.id else { return nil }
                return backend.id == .runtimeManaged ? choice : nil
            }()
        )
    }

    /// Prepares the prefix (first-run init, backend DLLs) and starts the process.
    @discardableResult
    public func launch(_ plan: LaunchPlan) throws -> Process {
        if !isPrefixInitialized(plan.bottle) {
            try initializePrefix(plan.bottle, runtime: plan.runtime, environment: plan.environment)
        }
        try installer.install(backend: plan.environment.backend, runtime: plan.runtime, bottle: plan.bottle)

        let process = makeProcess(
            executable: plan.executableURL,
            arguments: plan.arguments,
            environment: plan.environment.variables,
            workingDirectory: plan.workingDirectory,
            log: plan.environment.variables["WINEDEBUG"] == "-all" ? nil : logFile(for: plan.bottle)
        )
        try process.run()
        TetherLog.launch.info("Launched \(plan.arguments.first ?? "?", privacy: .public) in \(plan.bottle.name, privacy: .public) via \(plan.environment.backend.id.rawValue, privacy: .public)")
        return process
    }

    public func isPrefixInitialized(_ bottle: Bottle) -> Bool {
        FileManager.default.fileExists(atPath: bottle.prefixURL.appendingPathComponent("system.reg").path)
    }

    /// Runs `wineboot --init`, then sets the Windows version.
    public func initializePrefix(_ bottle: Bottle, runtime: WineRuntime, environment: LaunchEnvironment) throws {
        try runSync(runtime.wineBinary, ["wineboot", "--init"], environment: environment.variables, bottle: bottle)
        try runSync(runtime.wineBinary, ["winecfg", "-v", bottle.config.windowsVersion.rawValue], environment: environment.variables, bottle: bottle)
    }

    /// Stops every process in the bottle (`wineserver -k`).
    public func shutdown(_ bottle: Bottle) throws {
        let runtime = try runtimes.resolve(version: bottle.config.runtimeVersion)
        let env = ["WINEPREFIX": bottle.prefixURL.path, "PATH": "/usr/bin:/bin"]
        try runSync(runtime.wineserverBinary, ["-k"], environment: env, bottle: bottle)
    }

    // MARK: - Process helpers

    func makeProcess(executable: URL, arguments: [String], environment: [String: String], workingDirectory: URL, log: URL?) -> Process {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        p.environment = environment
        p.currentDirectoryURL = workingDirectory
        if let log, let handle = try? FileHandle.forWritingAtEnd(creatingIfNeeded: log) {
            p.standardOutput = handle
            p.standardError = handle
        } else {
            // Release launches discard output: no pipe to drain, no extra host work.
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
        }
        return p
    }

    private func runSync(_ exe: URL, _ args: [String], environment: [String: String], bottle: Bottle) throws {
        let p = makeProcess(executable: exe, arguments: args, environment: environment, workingDirectory: bottle.prefixURL, log: logFile(for: bottle))
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw LauncherError.commandFailed(([exe.lastPathComponent] + args).joined(separator: " "), p.terminationStatus)
        }
    }

    private func logFile(for bottle: Bottle) -> URL {
        bottle.logsURL.appendingPathComponent("wine.log")
    }
}

public enum LauncherError: Error, LocalizedError {
    case commandFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let code): return "'\(cmd)' exited with status \(code). See the bottle's logs/wine.log."
        }
    }
}

extension FileHandle {
    static func forWritingAtEnd(creatingIfNeeded url: URL) throws -> FileHandle {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: nil)
        }
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        return h
    }
}
