import Foundation
import Testing
@testable import TetherKit

@Suite struct CompatRuleRenderingTests {
    @Test func rendersTheDocumentedShapes() {
        #expect(CompatRule(.any, dxgi: .wined3d).render() == "exe=*;dxgi=wined3d")
        #expect(CompatRule(.steam(2357570), dxgi: .dxmt).render() == "exe=steam:2357570;dxgi=dxmt")
        #expect(CompatRule(.name("Game.exe"), d3d9: .wined3d, metalHUD: true).render() == "exe=Game.exe;d3d9=wined3d;metal_hud=true")
        #expect(CompatRule(.name("Game.exe"), dxgi: .dxmt, d3d9: .mtld3d, metalHUD: false).render() == "exe=Game.exe;dxgi=dxmt;d3d9=mtld3d;metal_hud=false")
    }

    @Test func escapesPercentAndSemicolon() {
        #expect(CompatRule(.name("A;B%C.exe"), dxgi: .dxmt).render() == "exe=A%3BB%25C.exe;dxgi=dxmt")
    }

    @Test(arguments: ["", "*", "a/b.exe", "a\\b.exe", "x:y.exe", "bad\u{0}.exe", "line\nbreak.exe", "tab\t.exe"])
    func invalidExeNamesAreRejected(name: String) {
        #expect(!CompatRule.isValidExeName(name))
    }

    @Test(arguments: ["Game.exe", "Overwatch.exe", "My Game (x64).exe", "é.exe"])
    func validExeNamesAreAccepted(name: String) {
        #expect(CompatRule.isValidExeName(name))
    }

    @Test func emptyRulesAreNeverWritten() {
        #expect(CompatRule(.any).isEmpty)
        var table = CompatTable()
        table.add(CompatRule(.name("a.exe")))
        #expect(table.rules.isEmpty && table.text.isEmpty)
        #expect(CompatTable([CompatRule(.any), CompatRule(.any, dxgi: .dxmt)]).rules.count == 1)
    }

    @Test func tableJoinsWithNewlinesAndNoTrailingBreak() {
        let table = CompatTable([CompatRule(.any, dxgi: .wined3d), CompatRule(.name("G.exe"), dxgi: .dxmt)])
        #expect(table.text == "exe=*;dxgi=wined3d\nexe=G.exe;dxgi=dxmt")
        #expect(table.disablesD3D12)
        #expect(!CompatTable([CompatRule(.any, dxgi: .dxmt)]).disablesD3D12)
    }
}

@Suite struct CompatRuleBuilderTests {
    let home = TempHome()

    private func bottle(backend: GraphicsBackendID? = nil, hud: Bool = false) throws -> Bottle {
        try BottleStore(paths: home.paths).create(name: "b-\(UUID().uuidString)", config: BottleConfig(backend: backend, showPerformanceHUD: hud))
    }

    let overwatch = GameProfile(
        id: "overwatch", name: "Overwatch 2", executables: ["Overwatch.exe"], steamAppIDs: [2357570],
        backendPreference: [.dxmt, .d3dmetal, .dxvk]
    )

    @Test func backendMapping() {
        #expect(CompatRuleBuilder.choice(for: .dxmt)?.dxgi == .dxmt)
        #expect(CompatRuleBuilder.choice(for: .dxmt)?.d3d9 == nil)
        #expect(CompatRuleBuilder.choice(for: .wined3d)?.dxgi == .wined3d)
        #expect(CompatRuleBuilder.choice(for: .wined3d)?.d3d9 == .wined3d)
        for unsupported in [GraphicsBackendID.dxvk, .d3dmetal, .runtimeManaged] {
            #expect(CompatRuleBuilder.choice(for: unsupported) == nil)
        }
        #expect(CompatRuleBuilder.firstSupported([.d3dmetal, .dxvk, .wined3d]) == .wined3d)
        #expect(CompatRuleBuilder.firstSupported([.dxvk]) == nil)
    }

    @Test func noChoicesMeansNoRules() throws {
        #expect(CompatRuleBuilder.build(bottle: try bottle(), profiles: [], launchedExecutable: "C:\\g.exe").rules.isEmpty)
        let noPreference = GameProfile(id: "x", name: "X", executables: ["x.exe"])
        #expect(CompatRuleBuilder.build(bottle: try bottle(), profiles: [noPreference], launchedExecutable: nil).rules.isEmpty)
    }

    @Test func explicitBottleBackendIsOneLaunchWideRuleAndBeatsProfiles() throws {
        let table = CompatRuleBuilder.build(bottle: try bottle(backend: .wined3d), profiles: [overwatch], launchedExecutable: nil)
        #expect(table.text == "exe=*;dxgi=wined3d;d3d9=wined3d")
    }

    @Test func unsupportedBottleBackendFallsThroughToProfiles() throws {
        let table = CompatRuleBuilder.build(bottle: try bottle(backend: .dxvk), profiles: [overwatch], launchedExecutable: nil)
        #expect(table.text == "exe=Overwatch.exe;dxgi=dxmt\nexe=steam:2357570;dxgi=dxmt")
    }

    @Test func profileUsesItsFirstSupportedPreference() throws {
        let p = GameProfile(id: "p", name: "P", executables: ["p.exe"], backendPreference: [.dxvk, .d3dmetal, .wined3d])
        let table = CompatRuleBuilder.build(bottle: try bottle(), profiles: [p], launchedExecutable: nil)
        #expect(table.text == "exe=p.exe;dxgi=wined3d;d3d9=wined3d")
        let unsupportedOnly = GameProfile(id: "q", name: "Q", executables: ["q.exe"], backendPreference: [.dxvk])
        #expect(CompatRuleBuilder.build(bottle: try bottle(), profiles: [unsupportedOnly], launchedExecutable: nil).rules.isEmpty)
    }

    @Test func invalidExecutablesAndAppIDsAreSkipped() throws {
        let p = GameProfile(id: "p", name: "P", executables: ["ok.exe", "bad/name.exe", "*"], steamAppIDs: [0, -3, 5, Int(UInt32.max) + 1],
                            backendPreference: [.dxmt])
        let table = CompatRuleBuilder.build(bottle: try bottle(), profiles: [p], launchedExecutable: nil)
        #expect(table.text == "exe=ok.exe;dxgi=dxmt\nexe=steam:5;dxgi=dxmt")
    }

    @Test func rulesAreOrderedByProfileIDForStableOutput() throws {
        let b = GameProfile(id: "b", name: "B", executables: ["b.exe"], backendPreference: [.dxmt])
        let a = GameProfile(id: "a", name: "A", executables: ["a.exe"], backendPreference: [.dxmt])
        let table = CompatRuleBuilder.build(bottle: try bottle(), profiles: [b, a], launchedExecutable: nil)
        #expect(table.rules.map(\.exe) == [.name("a.exe"), .name("b.exe")])
    }

    @Test func hudAttachesToTheLaunchedExecutable() throws {
        let alone = CompatRuleBuilder.build(bottle: try bottle(hud: true), profiles: [], launchedExecutable: "C:\\Games\\Game.exe")
        #expect(alone.text == "exe=Game.exe;metal_hud=true")

        let p = GameProfile(id: "g", name: "G", executables: ["game.exe"], backendPreference: [.dxmt])
        let merged = CompatRuleBuilder.build(bottle: try bottle(hud: true), profiles: [p], launchedExecutable: "C:\\Games\\Game.exe")
        #expect(merged.text == "exe=game.exe;dxgi=dxmt;metal_hud=true", "same program, one rule")
    }

    @Test func hudIsNeverPutOnTheSteamClient() throws {
        let table = CompatRuleBuilder.build(bottle: try bottle(hud: true), profiles: [], launchedExecutable: "C:\\Program Files (x86)\\Steam\\Steam.exe")
        #expect(table.rules.isEmpty)
        #expect(CompatRuleBuilder.build(bottle: try bottle(hud: false), profiles: [], launchedExecutable: "C:\\Game.exe").rules.isEmpty)
    }
}

@Suite struct CompatRulesLaunchTests {
    let home = TempHome()

    /// `rules`: a runtime that reads `WINE_COMPATDB_FILE`; `managed` alone is an older runtime that
    /// chooses graphics itself and has no rules support.
    private func runtime(managed: Bool, rules: Bool = true) throws -> WineRuntime {
        let root = home.paths.runtimes.appendingPathComponent("0.1.0")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var features = ["msync"]
        if managed { features.append("managed-graphics") }
        if managed && rules { features.append("compat-rules") }
        let manifest = RuntimeManifest(version: "0.1.0", wineVersion: "11.19", features: features, components: [])
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("runtime.json"))
        return WineRuntime(root: root, manifest: manifest)
    }

    @Test func rulesFileVariableIsOnlySetForManagedRuntimesAndIsProtected() throws {
        let bottle = try BottleStore(paths: home.paths).create(name: "b")
        let managed = try runtime(managed: true)
        let env = LaunchEnvironment(bottle: bottle, runtime: managed, backend: RuntimeManagedBackend(), profile: nil, paths: home.paths)
        #expect(env.variables["WINE_COMPATDB_FILE"] == bottle.compatRulesURL.path)
        #expect(env.variables["WINE_COMPATDB"] == nil)

        let plain = WineRuntime(root: managed.root, manifest: RuntimeManifest(version: "0.1.0", wineVersion: "1", features: [], components: []))
        let plainEnv = LaunchEnvironment(bottle: bottle, runtime: plain, backend: WineD3DBackend(), profile: nil, paths: home.paths)
        #expect(plainEnv.variables["WINE_COMPATDB_FILE"] == nil)

        #expect(LaunchEnvironment.isProtected("WINE_COMPATDB"))
        #expect(LaunchEnvironment.isProtected("WINE_COMPATDB_FILE"))
    }

    @Test func profilesAndBottlesCannotSetTheRulesVariables() throws {
        _ = try runtime(managed: true)
        var config = BottleConfig()
        config.environment = ["WINE_COMPATDB": "exe=*;env=EVIL=1", "WINE_COMPATDB_FILE": "/tmp/evil", "OK": "1"]
        let bottle = try BottleStore(paths: home.paths).create(name: "b", config: config)
        let env = LaunchEnvironment(bottle: bottle, runtime: try runtime(managed: true), backend: RuntimeManagedBackend(), profile: nil, paths: home.paths)
        #expect(env.variables["WINE_COMPATDB"] == nil)
        #expect(env.variables["WINE_COMPATDB_FILE"] == bottle.compatRulesURL.path)
        #expect(env.variables["OK"] == "1")
        #expect(env.rejectedEnvironmentKeys.sorted() == ["WINE_COMPATDB", "WINE_COMPATDB_FILE"])
    }

    @Test func planIsPureAndLaunchWritesTheFileAtomically() throws {
        _ = try runtime(managed: true)
        var config = BottleConfig()
        config.backend = .wined3d
        let bottle = try BottleStore(paths: home.paths).create(name: "b", config: config)
        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: []))

        let plan = try launcher.plan(LaunchRequest(bottle: bottle, executable: "C:\\g.exe"))
        #expect(plan.compatRules.text == "exe=*;dxgi=wined3d;d3d9=wined3d")
        #expect(!FileManager.default.fileExists(atPath: bottle.compatRulesURL.path), "planning must not write")

        try launcher.writeCompatRules(plan)
        #expect(try String(contentsOf: bottle.compatRulesURL, encoding: .utf8) == "exe=*;dxgi=wined3d;d3d9=wined3d\n")

        // A later launch replaces the content in place, e.g. when Steam is already running.
        var changed = bottle
        changed.config.backend = .dxmt
        let second = try launcher.plan(LaunchRequest(bottle: changed, executable: "C:\\g.exe"))
        try launcher.writeCompatRules(second)
        #expect(try String(contentsOf: bottle.compatRulesURL, encoding: .utf8) == "exe=*;dxgi=dxmt\n")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: bottle.root.path).filter { $0.contains("compat.rules") }
        #expect(leftovers == ["compat.rules"], "no temp files left behind")
    }

    @Test func emptyRulesWriteAnEmptyFileSoLaterLaunchesCanAddRules() throws {
        _ = try runtime(managed: true)
        let bottle = try BottleStore(paths: home.paths).create(name: "b")
        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: []))
        let plan = try launcher.plan(LaunchRequest(bottle: bottle, executable: "C:\\g.exe"))
        try launcher.writeCompatRules(plan)
        #expect(try String(contentsOf: bottle.compatRulesURL, encoding: .utf8) == "")
    }

    @Test func nonManagedRuntimeWritesNothing() throws {
        _ = try runtime(managed: false)
        let bottle = try BottleStore(paths: home.paths).create(name: "b")
        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: []))
        let plan = try launcher.plan(LaunchRequest(bottle: bottle, executable: "C:\\g.exe"))
        try launcher.writeCompatRules(plan)
        #expect(!FileManager.default.fileExists(atPath: bottle.compatRulesURL.path))
        #expect(plan.compatRules.rules.isEmpty)
    }

    @Test func runtimeWithoutRulesSupportGetsNoFileAndEveryChoiceIsReportedIgnored() throws {
        _ = try runtime(managed: true, rules: false)
        let store = BottleStore(paths: home.paths)
        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: [
            GameProfile(id: "p", name: "P", executables: ["p.exe"], backendPreference: [.dxmt]),
        ]))
        var b = try store.create(name: "old")
        b.config.backend = .wined3d
        let plan = try launcher.plan(LaunchRequest(bottle: b, executable: "C:\\p.exe"))
        #expect(plan.environment.variables["WINE_COMPATDB_FILE"] == nil)
        #expect(plan.compatRules.rules.isEmpty)
        #expect(plan.ignoredBackendChoice == .wined3d)
        try launcher.writeCompatRules(plan)
        #expect(!FileManager.default.fileExists(atPath: b.compatRulesURL.path))
    }

    @Test func onlyUnsupportedBottleBackendsAreReportedIgnored() throws {
        _ = try runtime(managed: true)
        let store = BottleStore(paths: home.paths)
        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: []))
        func ignored(_ backend: GraphicsBackendID?) throws -> GraphicsBackendID? {
            var b = try store.create(name: "b-\(backend?.rawValue ?? "none")")
            b.config.backend = backend
            return try launcher.plan(LaunchRequest(bottle: b, executable: "C:\\g.exe")).ignoredBackendChoice
        }
        #expect(try ignored(.dxmt) == nil)
        #expect(try ignored(.wined3d) == nil)
        #expect(try ignored(nil) == nil)
        #expect(try ignored(.dxvk) == .dxvk)
        #expect(try ignored(.d3dmetal) == .d3dmetal)
    }
}
