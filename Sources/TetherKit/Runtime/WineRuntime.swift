import Foundation

/// Describes a runtime build, stored as `runtime.json` at the runtime root.
/// Written by `runtime/scripts/package-runtime.sh`.
public struct RuntimeManifest: Codable, Hashable, Sendable {
    public struct Component: Codable, Hashable, Sendable {
        public var name: String       // "wine", "dxmt", "dxvk", "moltenvk", ...
        public var version: String
        public var source: String?    // upstream URL or git revision
    }

    public var version: String        // Tether runtime version, e.g. "0.1.0"
    public var wineVersion: String    // e.g. "10.0"
    public var features: [String]     // e.g. ["msync", "wow64"]
    public var components: [Component]
}

/// An installed Wine runtime: Wine itself plus the bundled open-source graphics backends.
///
/// Expected layout (native arm64 Wine with FEX, see ADR 0005):
/// ```
/// Runtimes/<version>/
///   runtime.json
///   bin/wine, bin/wineserver
///   lib/wine/{aarch64-unix,aarch64-windows,x86_64-windows,i386-windows}/
///   lib/wine/aarch64-unix/wine.app   signed loader that carries the cross-architecture entitlement
///   backends/<backend-id>/...        only for backends Tether bundles itself
/// ```
/// A wrapped community runtime ships its own DXMT and wined3d modules under `lib/wine/dxgi/` and
/// `lib/wine/d3d9/` and picks one per executable, so it may have no `backends/` directory.
public struct WineRuntime: Hashable, Sendable {
    public let root: URL
    public let manifest: RuntimeManifest

    public init(root: URL, manifest: RuntimeManifest) {
        self.root = root
        self.manifest = manifest
    }

    public var version: String { manifest.version }
    public var wineBinary: URL { root.appendingPathComponent("bin/wine") }
    public var wineserverBinary: URL { root.appendingPathComponent("bin/wineserver") }
    public var libDirectory: URL { root.appendingPathComponent("lib", isDirectory: true) }

    public func backendDirectory(for id: GraphicsBackendID) -> URL {
        root.appendingPathComponent("backends/\(id.rawValue)", isDirectory: true)
    }

    public func supports(feature: String) -> Bool { manifest.features.contains(feature) }
}

public enum RuntimeStoreError: Error, LocalizedError {
    case noRuntimesInstalled
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .noRuntimesInstalled: return "No Wine runtime installed. Run `tether runtime install`."
        case .notFound(let v): return "Runtime '\(v)' is not installed."
        }
    }
}

public struct RuntimeStore: Sendable {
    public let paths: TetherPaths

    public init(paths: TetherPaths = .default) {
        self.paths = paths
    }

    public func list() -> [WineRuntime] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: paths.runtimes, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries.compactMap { dir in
            let manifestURL = dir.appendingPathComponent("runtime.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(RuntimeManifest.self, from: data)
            else { return nil }
            return WineRuntime(root: dir, manifest: manifest)
        }
        .sorted { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
    }

    /// Resolves the runtime for a bottle: its pinned version, or the newest installed.
    public func resolve(version: String?) throws -> WineRuntime {
        let all = list()
        if let version {
            guard let match = all.first(where: { $0.version == version }) else {
                throw RuntimeStoreError.notFound(version)
            }
            return match
        }
        guard let latest = all.last else { throw RuntimeStoreError.noRuntimesInstalled }
        return latest
    }
}
