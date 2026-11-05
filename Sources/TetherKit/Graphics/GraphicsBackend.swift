import Foundation

public enum GraphicsBackendID: String, Codable, CaseIterable, Sendable {
    /// DXMT: D3D10/11 → Metal directly. Preferred for D3D11 titles (no Vulkan hop).
    case dxmt
    /// DXVK: D3D9/10/11 → Vulkan, then MoltenVK: Vulkan → Metal. Broadest compatibility.
    case dxvk
    /// Apple D3DMetal (from the Game Porting Toolkit). D3D11/12 → Metal.
    /// Not redistributable: the user must import it themselves.
    case d3dmetal
    /// Wine's built-in wined3d (D3D → OpenGL). Last-resort fallback.
    case wined3d
}

public enum DirectXAPI: String, Codable, CaseIterable, Sendable {
    case d3d9, d3d10, d3d11, d3d12
}

/// Per-launch knobs that affect backend environment.
public struct BackendOptions: Sendable {
    public var showHUD: Bool
    /// Where the backend may persist shader/pipeline caches.
    public var cacheDirectory: URL

    public init(showHUD: Bool = false, cacheDirectory: URL) {
        self.showHUD = showHUD
        self.cacheDirectory = cacheDirectory
    }
}

/// A DirectX translation backend.
///
/// Backends are passive: they describe which DLLs to place in the prefix, which
/// `WINEDLLOVERRIDES` to set, and which environment variables to export. They never
/// hook or inject into the game process — see docs/adr/0003-no-process-injection.md.
public protocol GraphicsBackend: Sendable {
    var id: GraphicsBackendID { get }
    var displayName: String { get }
    var supportedAPIs: Set<DirectXAPI> { get }

    /// DLLs (by base name, without `.dll`) this backend provides as PE files and must be
    /// copied into the prefix. Empty for backends built into the Wine runtime.
    var providedDLLs: [String] { get }

    /// Overrides needed so Wine loads this backend's DLLs instead of wined3d.
    var dllOverrides: [DLLOverride] { get }

    /// Whether the backend's files are present for the given runtime.
    func isAvailable(runtime: WineRuntime, paths: TetherPaths) -> Bool

    /// Directory containing `<arch>/<dll>.dll` for this backend.
    func sourceDirectory(runtime: WineRuntime, paths: TetherPaths) -> URL

    func environment(options: BackendOptions) -> [String: String]

    /// Extra directory to prepend to `WINEDLLPATH`, for backends whose DLLs are
    /// Wine-builtin modules loaded from outside the runtime (e.g. user-supplied D3DMetal).
    func builtinSearchPath(runtime: WineRuntime, paths: TetherPaths) -> URL?
}

public extension GraphicsBackend {
    func isAvailable(runtime: WineRuntime, paths: TetherPaths) -> Bool {
        FileManager.default.fileExists(atPath: sourceDirectory(runtime: runtime, paths: paths).path)
    }

    func sourceDirectory(runtime: WineRuntime, paths: TetherPaths) -> URL {
        runtime.backendDirectory(for: id)
    }

    func builtinSearchPath(runtime: WineRuntime, paths: TetherPaths) -> URL? { nil }
}

/// Registry of all known backends.
public enum GraphicsBackends {
    public static let all: [any GraphicsBackend] = [DXMTBackend(), DXVKBackend(), D3DMetalBackend(), WineD3DBackend()]

    public static func backend(for id: GraphicsBackendID) -> any GraphicsBackend {
        all.first { $0.id == id }!
    }

    /// Default preference when nothing else is specified: Metal-native first.
    public static let defaultOrder: [GraphicsBackendID] = [.dxmt, .d3dmetal, .dxvk, .wined3d]

    /// Picks the first available backend from, in order: the user's explicit bottle choice,
    /// the game profile's preference chain, then `defaultOrder`.
    public static func resolve(
        bottleChoice: GraphicsBackendID?,
        profile: GameProfile?,
        runtime: WineRuntime,
        paths: TetherPaths
    ) -> any GraphicsBackend {
        var order: [GraphicsBackendID] = []
        if let bottleChoice { order.append(bottleChoice) }
        if let profile { order.append(contentsOf: profile.backendPreference) }
        order.append(contentsOf: defaultOrder)

        var seen = Set<GraphicsBackendID>()
        for id in order where seen.insert(id).inserted {
            let backend = backend(for: id)
            if backend.isAvailable(runtime: runtime, paths: paths) { return backend }
        }
        return WineD3DBackend()
    }
}
