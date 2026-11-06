import Foundation

public struct DXMTBackend: GraphicsBackend {
    public init() {}
    public let id = GraphicsBackendID.dxmt
    public let displayName = "DXMT (D3D11 → Metal)"
    public let supportedAPIs: Set<DirectXAPI> = [.d3d10, .d3d11]
    // winemetal.dll is DXMT's PE↔unix bridge; its unix side (winemetal.so) lives in the runtime lib dir.
    public let providedDLLs = ["d3d11", "dxgi", "d3d10core", "winemetal"]
    public var dllOverrides: [DLLOverride] {
        ["d3d11", "dxgi", "d3d10core"].map { DLLOverride($0, .nativeThenBuiltin) }
    }

    public func environment(options: BackendOptions) -> [String: String] {
        var env: [String: String] = [
            "DXMT_LOG_LEVEL": "none",
        ]
        if options.showHUD { env["MTL_HUD_ENABLED"] = "1" }
        return env
    }
}

public struct DXVKBackend: GraphicsBackend {
    public init() {}
    public let id = GraphicsBackendID.dxvk
    public let displayName = "DXVK + MoltenVK (D3D9–11 → Vulkan → Metal)"
    public let supportedAPIs: Set<DirectXAPI> = [.d3d9, .d3d10, .d3d11]
    public let providedDLLs = ["d3d9", "d3d10core", "d3d11", "dxgi"]
    public var dllOverrides: [DLLOverride] {
        providedDLLs.map { DLLOverride($0, .nativeThenBuiltin) }
    }

    public func environment(options: BackendOptions) -> [String: String] {
        var env: [String: String] = [
            "DXVK_LOG_LEVEL": "none",
            "DXVK_STATE_CACHE_PATH": options.cacheDirectory.appendingPathComponent("dxvk").path,
            "MVK_CONFIG_LOG_LEVEL": "0",
            // Prefer recovering over crashing when Metal reports a lost device.
            "MVK_CONFIG_RESUME_LOST_DEVICE": "1",
        ]
        if options.showHUD { env["DXVK_HUD"] = "fps,frametimes,gpuload" }
        return env
    }
}

/// Apple's D3DMetal from the Game Porting Toolkit.
///
/// Its license does not permit redistribution, so Tether never ships it. Users run
/// `runtime/scripts/import-gptk.sh` to copy it from their own GPTK download into
/// `UserComponents/d3dmetal`.
public struct D3DMetalBackend: GraphicsBackend {
    public init() {}
    public let id = GraphicsBackendID.d3dmetal
    public let displayName = "D3DMetal (Apple GPTK, user-supplied)"
    public let supportedAPIs: Set<DirectXAPI> = [.d3d11, .d3d12]
    // GPTK's DLLs are Wine-builtin modules: they are loaded from WINEDLLPATH rather than
    // copied into the prefix, so nothing is installed into system32.
    public let providedDLLs: [String] = []
    public var dllOverrides: [DLLOverride] {
        ["d3d11", "d3d12", "dxgi"].map { DLLOverride($0, .builtin) }
    }

    public func sourceDirectory(runtime: WineRuntime, paths: TetherPaths) -> URL {
        paths.userComponents.appendingPathComponent("d3dmetal", isDirectory: true)
    }

    // TODO: verify against the current GPTK layout (x86_64-windows / x86_64-unix subdirs and
    // where D3DMetal.framework must live for the unix side to dlopen it).
    public func builtinSearchPath(runtime: WineRuntime, paths: TetherPaths) -> URL? {
        sourceDirectory(runtime: runtime, paths: paths)
    }

    public func environment(options: BackendOptions) -> [String: String] {
        var env: [String: String] = [:]
        if options.showHUD { env["MTL_HUD_ENABLED"] = "1" }
        return env
    }
}

/// Graphics chosen by the runtime, not by Tether (e.g. the wrapped community arm64 build, whose
/// compatibility database selects DXMT or wined3d per executable). Passive: no DLLs are copied,
/// no overrides are set, so the runtime's own selection is never disturbed.
public struct RuntimeManagedBackend: GraphicsBackend {
    public init() {}
    public let id = GraphicsBackendID.runtimeManaged
    public let displayName = "Runtime-managed (DXMT or wined3d, chosen per game by the runtime)"
    public let supportedAPIs: Set<DirectXAPI> = [.d3d9, .d3d10, .d3d11]
    public let providedDLLs: [String] = []
    public let dllOverrides: [DLLOverride] = []

    public func isAvailable(runtime: WineRuntime, paths: TetherPaths) -> Bool {
        runtime.supports(feature: GraphicsBackends.managedFeature)
    }

    public func environment(options: BackendOptions) -> [String: String] {
        options.showHUD ? ["MTL_HUD_ENABLED": "1"] : [:]
    }
}

public struct WineD3DBackend: GraphicsBackend {
    public init() {}
    public let id = GraphicsBackendID.wined3d
    public let displayName = "wined3d (OpenGL fallback)"
    public let supportedAPIs: Set<DirectXAPI> = [.d3d9, .d3d10, .d3d11]
    public let providedDLLs: [String] = []
    public let dllOverrides: [DLLOverride] = []

    /// Built into Wine, so it's always available.
    public func isAvailable(runtime: WineRuntime, paths: TetherPaths) -> Bool { true }

    public func environment(options: BackendOptions) -> [String: String] { [:] }
}
