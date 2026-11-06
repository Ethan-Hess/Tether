import Foundation
import Testing
@testable import TetherKit

@Suite struct LaunchEnvironmentTests {
    let home = TempHome()
    let runtime: WineRuntime
    let bottle: Bottle

    let overwatch = GameProfile(
        id: "overwatch", name: "Overwatch 2", executables: ["Overwatch.exe"],
        backendPreference: [.dxmt, .d3dmetal, .dxvk], sync: .msync
    )

    init() throws {
        runtime = WineRuntime(
            root: home.paths.runtimes.appendingPathComponent("0.1.0"),
            manifest: RuntimeManifest(version: "0.1.0", wineVersion: "10.0", features: ["msync", "wow64"], components: [])
        )
        // Pretend DXMT and DXVK ship with the runtime; D3DMetal is not imported.
        for id in [GraphicsBackendID.dxmt, .dxvk] {
            try FileManager.default.createDirectory(at: runtime.backendDirectory(for: id), withIntermediateDirectories: true)
        }
        bottle = try BottleStore(paths: home.paths).create(name: "ow")
    }

    @Test func overwatchProfileUsesDXMTWithMsync() {
        let backend = GraphicsBackends.resolve(bottleChoice: nil, profile: overwatch, runtime: runtime, paths: home.paths)
        #expect(backend.id == .dxmt)

        let env = LaunchEnvironment(
            bottle: bottle, runtime: runtime, backend: backend, profile: overwatch, paths: home.paths,
            options: .init(baseEnvironment: ["HOME": "/Users/x", "DYLD_INSERT_LIBRARIES": "/evil.dylib"])
        )
        let v = env.variables
        #expect(v["WINEPREFIX"] == bottle.prefixURL.path)
        #expect(v["WINEMSYNC"] == "1")
        #expect(v["WINEESYNC"] == nil)
        #expect(v["WINEDEBUG"] == "-all")
        #expect(v["WINEDLLOVERRIDES"] == "d3d10core,d3d11,dxgi=n,b;winemenubuilder.exe=")
        #expect(v["HOME"] == "/Users/x")
        #expect(v["DYLD_INSERT_LIBRARIES"] == nil, "host DYLD_* must never leak into the game")
    }

    @Test func bottleChoiceBeatsProfile() {
        let backend = GraphicsBackends.resolve(bottleChoice: .dxvk, profile: overwatch, runtime: runtime, paths: home.paths)
        #expect(backend.id == .dxvk)
    }

    @Test func unavailableBackendFallsThrough() {
        let backend = GraphicsBackends.resolve(bottleChoice: .d3dmetal, profile: nil, runtime: runtime, paths: home.paths)
        #expect(backend.id == .dxmt)
    }

    @Test func msyncDegradesToEsyncWithoutRuntimeSupport() {
        let noMsync = WineRuntime(
            root: runtime.root,
            manifest: RuntimeManifest(version: "0.1.0", wineVersion: "10.0", features: [], components: [])
        )
        let env = LaunchEnvironment(bottle: bottle, runtime: noMsync, backend: DXMTBackend(), profile: overwatch, paths: home.paths)
        #expect(env.variables["WINEMSYNC"] == nil)
        #expect(env.variables["WINEESYNC"] == "1")
    }

    @Test func policyBlocksNonTranslationOverridesAndProtectedKeys() {
        var profile = overwatch
        profile.dllOverrides = [DLLOverride("xaudio2_7", .native), DLLOverride("someoverlay", .native)]
        profile.environment = ["WINEDLLOVERRIDES": "x=n", "DYLD_INSERT_LIBRARIES": "/x.dylib", "SOME_FLAG": "1"]

        let env = LaunchEnvironment(bottle: bottle, runtime: runtime, backend: DXMTBackend(), profile: profile, paths: home.paths)
        let overrides = env.variables["WINEDLLOVERRIDES"] ?? ""
        #expect(env.rejectedOverrides.map(\.dll) == ["someoverlay"])
        #expect(env.rejectedEnvironmentKeys == ["DYLD_INSERT_LIBRARIES", "WINEDLLOVERRIDES"])
        #expect(env.variables["SOME_FLAG"] == "1")
        #expect(overrides.contains("xaudio2_7=n"))
        #expect(!overrides.contains("someoverlay"))
    }

    @Test func builtinProfilesDecodeAndMatch() {
        let lib = ProfileLibrary.load(paths: home.paths)
        #expect(lib.profile(id: "overwatch") != nil)
        #expect(lib.match(executable: #"C:\Program Files (x86)\Overwatch\_retail_\Overwatch.exe"#)?.id == "overwatch")
        #expect(lib.match(steamAppID: 2357570)?.id == "overwatch")
        #expect(lib.profile(id: "steam") != nil)
        #expect(lib.profile(id: "battlenet") == nil, "Battle.net is out of scope")
    }

    @Test func backendInstallPlan() {
        let installer = BackendInstaller(paths: home.paths)
        let steps = installer.plan(backend: DXVKBackend(), runtime: runtime, bottle: bottle)
        #expect(steps.count == 8) // 4 DLLs × 2 arches
        #expect(steps.contains { $0.destination.path.hasSuffix("windows/system32/d3d11.dll") && $0.source.path.contains("/x86_64/") })
        #expect(steps.contains { $0.destination.path.hasSuffix("windows/syswow64/d3d11.dll") && $0.source.path.contains("/i386/") })
        #expect(installer.plan(backend: D3DMetalBackend(), runtime: runtime, bottle: bottle).isEmpty)
    }
}
