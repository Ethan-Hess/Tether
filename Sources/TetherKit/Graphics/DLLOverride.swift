import Foundation

/// One entry in `WINEDLLOVERRIDES`.
public struct DLLOverride: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case native = "n"
        case builtin = "b"
        case nativeThenBuiltin = "n,b"
        case builtinThenNative = "b,n"
        case disabled = ""
    }

    public var dll: String
    public var mode: Mode

    public init(_ dll: String, _ mode: Mode) {
        self.dll = dll.lowercased()
        self.mode = mode
    }

    /// Renders overrides as `WINEDLLOVERRIDES`, grouping DLLs that share a mode.
    /// Later entries for the same DLL win. Output is deterministic (sorted).
    public static func render(_ overrides: [DLLOverride]) -> String {
        var byDLL: [String: Mode] = [:]
        for o in overrides { byDLL[o.dll] = o.mode }

        var byMode: [Mode: [String]] = [:]
        for (dll, mode) in byDLL { byMode[mode, default: []].append(dll) }

        return byMode
            .map { mode, dlls in "\(dlls.sorted().joined(separator: ","))=\(mode.rawValue)" }
            .sorted()
            .joined(separator: ";")
    }
}

/// Enforces ADR 0003: profiles and bottles may only override DLLs that belong to the
/// graphics/media translation surface. Anything else (overlays, hook DLLs, arbitrary
/// injected modules) is dropped. This keeps the game's address space limited to Wine plus
/// standard translation layers — the same thing every Proton/CrossOver user runs.
public enum OverridePolicy {
    public static let allowedDLLs: Set<String> = [
        // Direct3D / DXGI
        "d3d8", "d3d9", "d3d10", "d3d10_1", "d3d10core", "d3d11", "d3d12", "d3d12core", "dxgi",
        "winemetal", "ddraw",
        // Shader compiler / helpers
        "d3dcompiler_43", "d3dcompiler_46", "d3dcompiler_47", "d3dx9_43", "d3dx11_43",
        // Media / audio commonly swapped for compatibility
        "xaudio2_7", "xaudio2_8", "xaudio2_9", "x3daudio1_7", "xactengine3_7", "mfplat",
        // Browser-based launchers
        "libglesv2",
    ]

    public static func filter(_ overrides: [DLLOverride]) -> (allowed: [DLLOverride], rejected: [DLLOverride]) {
        var allowed: [DLLOverride] = []
        var rejected: [DLLOverride] = []
        for o in overrides {
            if allowedDLLs.contains(o.dll) { allowed.append(o) } else { rejected.append(o) }
        }
        return (allowed, rejected)
    }
}
