import ArgumentParser
import Foundation
import TetherKit

struct Tether: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tether",
        abstract: "Run Windows games on macOS with Wine + Metal.",
        subcommands: [BottleCommand.self, Run.self, Env.self, RuntimeCommand.self, Backends.self, Profiles.self, Doctor.self]
    )
}

// MARK: - bottle

struct BottleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bottle",
        abstract: "Manage bottles (isolated Wine prefixes).",
        subcommands: [Create.self, List.self, Info.self, Remove.self, Set.self, Kill.self]
    )

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a bottle.")
        @Argument var name: String
        @Option(help: "Game profile id (see `tether profiles`).") var profile: String?
        @Option(help: "Force a graphics backend: \(GraphicsBackendID.allCases.map(\.rawValue).joined(separator: ", ")).")
        var backend: GraphicsBackendID?
        @Option var windows: WindowsVersion = .win10

        func run() throws {
            let bottle = try BottleStore().create(
                name: name,
                config: BottleConfig(backend: backend, profileID: profile, windowsVersion: windows)
            )
            print("Created bottle '\(bottle.name)' at \(bottle.root.path)")
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List bottles.")
        func run() throws {
            let bottles = try BottleStore().list()
            if bottles.isEmpty { print("No bottles. Create one with `tether bottle create <name>`."); return }
            for b in bottles {
                let backend = b.config.backend?.rawValue ?? "auto"
                let profile = b.config.profileID ?? "-"
                print("\(b.name)\tbackend=\(backend)\tprofile=\(profile)\twindows=\(b.config.windowsVersion.rawValue)")
            }
        }
    }

    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show a bottle's configuration.")
        @Argument var name: String
        func run() throws {
            let b = try BottleStore().load(name: name)
            let data = try String(contentsOf: b.configURL, encoding: .utf8)
            print("Path: \(b.root.path)\n\(data)")
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm", abstract: "Delete a bottle and everything in it.")
        @Argument var name: String
        @Flag(name: .shortAndLong, help: "Don't ask for confirmation.") var force = false
        func run() throws {
            if !force {
                print("Delete bottle '\(name)' and all installed games in it? [y/N] ", terminator: "")
                guard readLine()?.lowercased() == "y" else { print("Aborted."); return }
            }
            try BottleStore().delete(name: name)
            print("Deleted '\(name)'.")
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Change a bottle setting.")
        @Argument var name: String
        @Option var backend: String?
        @Option var profile: String?
        @Option var sync: SyncMode?
        @Option(help: "Show the backend's performance HUD (true/false).") var hud: Bool?
        @Option(name: .customLong("env"), help: "KEY=VALUE (repeatable). Empty value removes the key.")
        var env: [String] = []

        func run() throws {
            let store = BottleStore()
            var b = try store.load(name: name)
            if let backend { b.config.backend = backend == "auto" ? nil : GraphicsBackendID(rawValue: backend) }
            if let profile { b.config.profileID = profile == "none" ? nil : profile }
            if let sync { b.config.sync = sync }
            if let hud { b.config.showPerformanceHUD = hud }
            for pair in env {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard let key = parts.first, !key.isEmpty else { continue }
                let value = parts.count > 1 ? parts[1] : ""
                b.config.environment[key] = value.isEmpty ? nil : value
            }
            try store.save(b)
            print("Updated '\(name)'.")
        }
    }

    struct Kill: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop all processes in a bottle (wineserver -k).")
        @Argument var name: String
        func run() throws {
            try Launcher().shutdown(try BottleStore().load(name: name))
        }
    }
}

// MARK: - run / env

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run a Windows executable in a bottle.")
    @Argument var bottle: String
    @Argument(help: "Windows path (C:\\...) or host path to a .exe") var executable: String
    @Argument(parsing: .captureForPassthrough) var arguments: [String] = []
    @Option var profile: String?
    @Flag(help: "Enable Wine/backend logging to the bottle's logs/wine.log.") var debug = false
    @Flag(help: "Wait for the process to exit.") var wait = false

    func run() throws {
        let launcher = Launcher()
        let b = try BottleStore().load(name: bottle)
        let plan = try launcher.plan(LaunchRequest(bottle: b, executable: executable, arguments: arguments, profileID: profile, debug: debug))
        printPolicyWarnings(plan.environment)
        let process = try launcher.launch(plan)
        print("Started (pid \(process.processIdentifier)) with \(plan.environment.backend.displayName)")
        if wait {
            process.waitUntilExit()
            throw ExitCode(process.terminationStatus)
        }
    }
}

struct Env: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print the environment a launch would use, without launching.")
    @Argument var bottle: String
    @Argument var executable: String
    @Option var profile: String?
    @Flag var debug = false

    func run() throws {
        let b = try BottleStore().load(name: bottle)
        let plan = try Launcher().plan(LaunchRequest(bottle: b, executable: executable, profileID: profile, debug: debug))
        print("# runtime: \(plan.runtime.version)")
        print("# backend: \(plan.environment.backend.displayName)")
        print("# profile: \(plan.environment.profile?.name ?? "none")")
        printPolicyWarnings(plan.environment)
        for (k, v) in plan.environment.variables.sorted(by: { $0.key < $1.key }) {
            print("\(k)=\(v)")
        }
        print("# exec: \(([plan.executableURL.path] + plan.arguments).joined(separator: " "))")
    }
}

func printPolicyWarnings(_ env: LaunchEnvironment) {
    for o in env.rejectedOverrides {
        FileHandle.standardError.write("warning: DLL override '\(o.dll)' blocked by policy (docs/adr/0003-no-process-injection.md)\n".data(using: .utf8)!)
    }
    for k in env.rejectedEnvironmentKeys {
        FileHandle.standardError.write("warning: environment key '\(k)' is protected and was ignored\n".data(using: .utf8)!)
    }
}

// MARK: - info commands

struct RuntimeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runtime",
        abstract: "List and install Wine runtimes.",
        subcommands: [List.self, Install.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List installed runtimes.")
        func run() {
            let all = RuntimeStore().list()
            if all.isEmpty { print("No runtimes installed. Run `tether runtime install`."); return }
            for r in all {
                let comps = r.manifest.components.map { "\($0.name) \($0.version)" }.joined(separator: ", ")
                print("\(r.version)\twine \(r.manifest.wineVersion)\t[\(r.manifest.features.joined(separator: ","))]\t\(comps)")
            }
        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download, verify and install a runtime.")
        @Argument(help: "Runtime version (default: newest in the catalog).") var version: String?

        func run() throws {
            guard let source = RuntimeCatalog.bundled().source(version: version) else {
                throw ValidationError("No runtime \(version.map { "'\($0)'" } ?? "") in the catalog.")
            }
            let mb = Double(source.size) / 1_000_000
            print("Installing runtime \(source.version) (wine \(source.wineVersion)), \(String(format: "%.0f", mb)) MB from \(source.url.host ?? "?")…")
            print("The download is verified against a pinned SHA-256 before anything is unpacked.")
            do {
                let runtime = try blocking { try await RuntimeInstaller().install(source) }
                print("Installed \(runtime.version) at \(runtime.root.path)")
            } catch RuntimeInstallError.alreadyInstalled(let v) {
                print("Runtime \(v) is already installed.")
            }
        }
    }
}

/// Runs async work from a synchronous command and returns its result.
final class ResultBox<T>: @unchecked Sendable { var result: Result<T, Error>? }

func blocking<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task {
        do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
        done.signal()
    }
    done.wait()
    return try box.result!.get()
}

struct Backends: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List graphics backends and availability.")
    func run() {
        let paths = TetherPaths.default
        let runtime = try? RuntimeStore(paths: paths).resolve(version: nil)
        for b in GraphicsBackends.all {
            let available = runtime.map { b.isAvailable(runtime: $0, paths: paths) } ?? false
            let apis = b.supportedAPIs.map(\.rawValue).sorted().joined(separator: ",")
            print("\(available ? "✓" : "✗") \(b.id.rawValue)\t\(apis)\t\(b.displayName)")
        }
    }
}

struct Profiles: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List game profiles.")
    func run() {
        for p in ProfileLibrary.load().profiles {
            print("\(p.id)\t\(p.name)\tbackends=\(p.backendPreference.map(\.rawValue).joined(separator: ">"))")
        }
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check that this Mac is ready to run Tether.")
    func run() {
        for item in SystemCheck.run().items {
            print("\(item.ok ? "✓" : "✗") \(item.name): \(item.detail)")
        }
    }
}

extension GraphicsBackendID: ExpressibleByArgument {}
extension WindowsVersion: ExpressibleByArgument {}
extension SyncMode: ExpressibleByArgument {}

Tether.main()
