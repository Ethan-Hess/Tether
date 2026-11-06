import Foundation
import Testing
@testable import TetherKit

/// Runtimes that choose their own graphics backend (the wrapped community arm64 build, ADR 0005).
@Suite struct ManagedGraphicsTests {
    let home = TempHome()
    let managed: WineRuntime
    let bottle: Bottle

    init() throws {
        managed = WineRuntime(
            root: home.paths.runtimes.appendingPathComponent("0.1.0"),
            manifest: RuntimeManifest(
                version: "0.1.0", wineVersion: "11.19",
                features: ["msync", "managed-graphics"], components: []
            )
        )
        // Even if Tether-style backend directories exist, a managed runtime must not use them.
        try FileManager.default.createDirectory(at: managed.backendDirectory(for: .dxmt), withIntermediateDirectories: true)
        bottle = try BottleStore(paths: home.paths).create(name: "m")
    }

    @Test func managedRuntimeResolvesToRuntimeManaged() {
        let profile = GameProfile(id: "p", name: "P", executables: ["p.exe"], backendPreference: [.dxmt], sync: .msync)
        let backend = GraphicsBackends.resolve(bottleChoice: .dxvk, profile: profile, runtime: managed, paths: home.paths)
        #expect(backend.id == .runtimeManaged)
    }

    @Test func managedBackendSetsNoOverridesAndInstallsNothing() {
        let backend = RuntimeManagedBackend()
        let env = LaunchEnvironment(bottle: bottle, runtime: managed, backend: backend, profile: nil, paths: home.paths)
        // Only the policy-owned winemenubuilder override; nothing that would fight the runtime's own choice.
        #expect(env.variables["WINEDLLOVERRIDES"] == "winemenubuilder.exe=")
        #expect(env.variables["WINEDLLPATH"] == nil)
        #expect(BackendInstaller(paths: home.paths).plan(backend: backend, runtime: managed, bottle: bottle).isEmpty)
    }

    @Test func hudGoesThroughRulesNotEnvironment() {
        // The runtime's authors ask launchers to use the metal_hud rule, not MTL_HUD_ variables.
        let on = RuntimeManagedBackend().environment(options: BackendOptions(showHUD: true, cacheDirectory: home.root))
        #expect(on.isEmpty)
    }

    @Test func planReportsIgnoredForcedBackend() throws {
        try writeRuntime()
        var b = bottle
        b.config.backend = .dxvk
        try BottleStore(paths: home.paths).save(b)

        let plan = try Launcher(paths: home.paths).plan(LaunchRequest(bottle: b, executable: "C:\\game.exe"))
        #expect(plan.environment.backend.id == .runtimeManaged)
        #expect(plan.ignoredBackendChoice == .dxvk)
    }

    @Test func noNoticeWhenNothingWasForced() throws {
        try writeRuntime()
        let plan = try Launcher(paths: home.paths).plan(LaunchRequest(bottle: bottle, executable: "C:\\game.exe"))
        #expect(plan.ignoredBackendChoice == nil)
    }

    @Test func nonManagedRuntimeStillHonoursChoice() {
        let plain = WineRuntime(
            root: home.paths.runtimes.appendingPathComponent("plain"),
            manifest: RuntimeManifest(version: "plain", wineVersion: "10.0", features: ["msync"], components: [])
        )
        let backend = GraphicsBackends.resolve(bottleChoice: .dxmt, profile: nil, runtime: plain, paths: home.paths)
        #expect(backend.id == .wined3d, "no managed feature and no DXMT files: falls through to wined3d as before")
    }

    private func writeRuntime() throws {
        let data = try JSONEncoder().encode(managed.manifest)
        try FileManager.default.createDirectory(at: managed.root, withIntermediateDirectories: true)
        try data.write(to: managed.root.appendingPathComponent("runtime.json"))
    }
}
