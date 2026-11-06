import Foundation
import Testing
@testable import TetherKit

@Suite struct KeyValuesTests {
    @Test func parsesNestedObjectsAndStrings() throws {
        let doc = try KeyValues.parse("""
        "AppState"
        {
            "appid"   "730"
            "name"    "Counter-Strike 2"
            "UserConfig" { "language" "english" }
        }
        """)
        #expect(doc["AppState"]?["appid"]?.string == "730")
        #expect(doc["appstate"]?["NAME"]?.string == "Counter-Strike 2", "lookups are case-insensitive")
        #expect(doc["AppState"]?["UserConfig"]?["language"]?.string == "english")
        #expect(doc["AppState"]?["missing"] == nil)
    }

    @Test func handlesEscapesCommentsBOMAndUnquotedTokens() throws {
        let text = "\u{FEFF}// comment\n\"a\" \"C:\\\\Games\\\\x\" // trailing\n\"b\" \"line1\\nq\\\"uote\\\"\"\nplain value\n"
        let doc = try KeyValues.parse(text)
        #expect(doc["a"]?.string == "C:\\Games\\x")
        #expect(doc["b"]?.string == "line1\nq\"uote\"")
        #expect(doc["plain"]?.string == "value")
    }

    @Test func repeatedKeysArePreservedInOrder() throws {
        let doc = try KeyValues.parse("\"k\" \"1\" \"k\" \"2\"")
        #expect(doc.entries.map(\.key) == ["k", "k"])
        #expect(doc["k"]?.string == "1")
    }

    @Test(arguments: [
        "\"a\" \"unterminated",
        "\"a\" {",
        "\"a\" { \"b\" \"c\" ",
        "}",
        "\"a\" }",
        "{ \"a\" \"b\" }",
    ])
    func malformedInputThrows(text: String) {
        #expect(throws: KeyValuesError.self) { try KeyValues.parse(text) }
    }

    @Test func deepNestingIsRejectedNotCrashed() {
        let deep = String(repeating: "\"k\" {", count: 500) + String(repeating: "}", count: 500)
        #expect(throws: KeyValuesError.tooDeep) { try KeyValues.parse(deep) }
    }

    @Test func emptyDocumentIsEmptyObject() throws {
        #expect(try KeyValues.parse("  \n// nothing\n") == .object([]))
    }
}

@Suite struct SteamLibraryTests {
    let home = TempHome()

    static let newFormat = """
    "libraryfolders"
    {
        "0" { "path" "C:\\\\Program Files (x86)\\\\Steam" "label" "" "apps" { "730" "1234" } }
        "1" { "path" "D:\\\\SteamLibrary" "apps" { "570" "99" } }
    }
    """

    static func manifest(id: Int, name: String, dir: String, flags: Int = 4) -> String {
        """
        "AppState"
        {
            "appid" "\(id)"
            "name" "\(name)"
            "installdir" "\(dir)"
            "StateFlags" "\(flags)"
            "SizeOnDisk" "123456"
            "LastUpdated" "1700000000"
            "buildid" "42"
        }
        """
    }

    @Test func libraryFoldersCurrentAndLegacyFormats() throws {
        #expect(try SteamLibrary.libraryFolders(vdf: Self.newFormat) == ["C:\\Program Files (x86)\\Steam", "D:\\SteamLibrary"])
        let legacy = "\"LibraryFolders\" { \"TimeNextStatsReport\" \"1\" \"ContentStatsID\" \"7\" \"1\" \"E:\\\\Games\" }"
        #expect(try SteamLibrary.libraryFolders(vdf: legacy) == ["E:\\Games"])
        #expect(try SteamLibrary.libraryFolders(vdf: "\"other\" { }").isEmpty)
    }

    @Test func parsesAppManifest() throws {
        let root = URL(fileURLWithPath: "/lib")
        let app = try SteamLibrary.parseAppManifest(Self.manifest(id: 730, name: "Counter-Strike 2", dir: "Counter-Strike Global Offensive"), libraryRoot: root)
        #expect(app.appID == 730)
        #expect(app.name == "Counter-Strike 2")
        #expect(app.installURL.path == "/lib/steamapps/common/Counter-Strike Global Offensive")
        #expect(app.sizeOnDisk == 123456)
        #expect(app.buildID == "42")
        #expect(app.lastUpdated == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(app.isFullyInstalled)
    }

    @Test func incompleteInstallIsFlagged() throws {
        let app = try SteamLibrary.parseAppManifest(Self.manifest(id: 1, name: "X", dir: "x", flags: 1026), libraryRoot: home.root)
        #expect(!app.isFullyInstalled)
    }

    @Test func missingNameFallsBackToAppID() throws {
        let app = try SteamLibrary.parseAppManifest("\"AppState\" { \"appid\" \"7\" \"installdir\" \"seven\" }", libraryRoot: home.root)
        #expect(app.name == "App 7")
        #expect(app.stateFlags == nil && app.isFullyInstalled)
    }

    @Test(arguments: ["../../etc", "..", ".", "a/b", "a\\b", ""])
    func unsafeInstallDirRejected(dir: String) {
        let text = "\"AppState\" { \"appid\" \"1\" \"installdir\" \"\(dir.replacingOccurrences(of: "\\", with: "\\\\"))\" }"
        #expect(throws: SteamLibraryError.self) { try SteamLibrary.parseAppManifest(text, libraryRoot: home.root) }
    }

    @Test(arguments: ["0", "-5", "abc", ""])
    func invalidAppIDRejected(id: String) {
        let text = "\"AppState\" { \"appid\" \"\(id)\" \"installdir\" \"x\" }"
        #expect(throws: SteamLibraryError.self) { try SteamLibrary.parseAppManifest(text, libraryRoot: home.root) }
    }

    @Test func nonManifestDocumentRejected() {
        #expect(throws: SteamLibraryError.notAnAppManifest) { try SteamLibrary.parseAppManifest("\"x\" { }", libraryRoot: home.root) }
    }

    @Test func manifestFileNameFilter() {
        #expect(SteamLibrary.isAppManifestName("appmanifest_730.acf"))
        for bad in ["appmanifest_.acf", "appmanifest_abc.acf", "appmanifest_730.acf.bak", "manifest_730.acf", "appmanifest_7 3.acf"] {
            #expect(!SteamLibrary.isAppManifestName(bad), "\(bad)")
        }
    }

    /// Two libraries (C: and D: via dosdevices), a duplicate id, a broken manifest and a stray file.
    @Test func scansAcrossLibrariesInABottle() throws {
        let fm = FileManager.default
        let bottle = try BottleStore(paths: home.paths).create(name: "steam")
        let steam = bottle.driveC.appendingPathComponent(SteamLibrary.defaultRootInBottle)
        let second = home.root.appendingPathComponent("second-library")

        func write(_ text: String, _ url: URL) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write(Self.newFormat, steam.appendingPathComponent("steamapps/libraryfolders.vdf"))
        try write(Self.manifest(id: 730, name: "Counter-Strike 2", dir: "cs2"), steam.appendingPathComponent("steamapps/appmanifest_730.acf"))
        try write(Self.manifest(id: 570, name: "Dota 2", dir: "dota"), second.appendingPathComponent("SteamLibrary/steamapps/appmanifest_570.acf"))
        try write(Self.manifest(id: 730, name: "Duplicate", dir: "dup"), second.appendingPathComponent("SteamLibrary/steamapps/appmanifest_730.acf"))
        try write("not a manifest {{{", steam.appendingPathComponent("steamapps/appmanifest_999.acf"))
        try write("ignored", steam.appendingPathComponent("steamapps/readme.txt"))

        // D: -> second-library (as Wine's dosdevices would be)
        try fm.createDirectory(at: bottle.prefixURL.appendingPathComponent("dosdevices"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: bottle.prefixURL.appendingPathComponent("dosdevices/d:").path, withDestinationPath: second.path)

        let apps = SteamLibrary.installedApps(in: bottle)
        #expect(apps.map(\.appID) == [730, 570], "sorted by name: Counter-Strike 2, then Dota 2")
        #expect(apps.first { $0.appID == 730 }?.name == "Counter-Strike 2", "first library wins for a duplicate id")
        #expect(apps.first { $0.appID == 570 }?.installURL.path == second.appendingPathComponent("SteamLibrary/steamapps/common/dota").path)
        #expect(apps.count == 2, "the broken manifest and stray file are skipped")
    }

    @Test func emptyBottleHasNoApps() throws {
        let bottle = try BottleStore(paths: home.paths).create(name: "empty")
        #expect(SteamLibrary.installedApps(in: bottle).isEmpty)
    }

    @Test func windowsPathMapping() throws {
        let fm = FileManager.default
        let bottle = try BottleStore(paths: home.paths).create(name: "paths")
        #expect(bottle.hostURL(forWindowsPath: "C:\\Program Files\\Steam")?.path == bottle.driveC.appendingPathComponent("Program Files/Steam").path)
        #expect(bottle.hostURL(forWindowsPath: "c:/Games")?.path == bottle.driveC.appendingPathComponent("Games").path)
        #expect(bottle.hostURL(forWindowsPath: "C:\\..\\..\\etc") == nil, "no traversal")
        #expect(bottle.hostURL(forWindowsPath: "relative\\path") == nil)
        #expect(bottle.hostURL(forWindowsPath: "/unix/path") == nil)
        #expect(bottle.hostURL(forWindowsPath: "Q:\\x") == nil, "unknown drive")

        // relative dosdevices symlink, like Wine creates for c:
        let dev = bottle.prefixURL.appendingPathComponent("dosdevices")
        try fm.createDirectory(at: dev, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: dev.appendingPathComponent("e:").path, withDestinationPath: "../drive_c")
        #expect(bottle.hostURL(forWindowsPath: "E:\\Games")?.path.hasSuffix("/prefix/drive_c/Games") == true)
    }
}

@Suite struct SteamProfileMatchingTests {
    let home = TempHome()
    let cs2 = GameProfile(id: "cs2", name: "CS2", executables: ["cs2.exe"], steamAppIDs: [730])
    let other = GameProfile(id: "other", name: "Other", executables: ["game.exe"], steamAppIDs: [111, 222])

    @Test func matchesBySteamAppID() {
        let lib = ProfileLibrary(profiles: [cs2, other])
        #expect(lib.match(steamAppID: 222)?.id == "other")
        #expect(lib.match(steamAppID: 5) == nil)
    }

    @Test func profilesWithoutSteamAppIDsStillDecode() throws {
        let p = try JSONDecoder().decode(GameProfile.self, from: Data(#"{"id":"x","name":"X"}"#.utf8))
        #expect(p.steamAppIDs.isEmpty)
        let q = try JSONDecoder().decode(GameProfile.self, from: Data(#"{"id":"x","name":"X","steamAppIDs":[1,2]}"#.utf8))
        #expect(q.steamAppIDs == [1, 2])
    }

    @Test func appIDBeatsExecutableNameInLaunchRequests() throws {
        let bottle = try BottleStore(paths: home.paths).create(name: "b")
        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: [cs2, other]))
        // Exe name says "cs2", app ID says "other": the app ID wins.
        let byID = launcher.resolveProfile(for: LaunchRequest(bottle: bottle, executable: "C:\\x\\cs2.exe", steamAppID: 111))
        #expect(byID?.id == "other")
        let byExe = launcher.resolveProfile(for: LaunchRequest(bottle: bottle, executable: "C:\\x\\cs2.exe"))
        #expect(byExe?.id == "cs2")
        // An explicit profile id still beats everything.
        let explicit = launcher.resolveProfile(for: LaunchRequest(bottle: bottle, executable: "C:\\x\\cs2.exe", profileID: "cs2", steamAppID: 111))
        #expect(explicit?.id == "cs2")
    }
}

@Suite struct LaunchArgumentTests {
    let home = TempHome()

    private func installRuntime() throws {
        let root = home.paths.runtimes.appendingPathComponent("0.1.0")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = RuntimeManifest(version: "0.1.0", wineVersion: "11.19", features: ["msync"], components: [])
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("runtime.json"))
    }

    @Test func profileArgumentsComeBeforeUserArguments() throws {
        try installRuntime()
        let profile = GameProfile(id: "g", name: "G", executables: ["g.exe"], launchArguments: ["-a", "-b"])
        let bottle = try BottleStore(paths: home.paths).create(name: "b")
        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: [profile]))
        let plan = try launcher.plan(LaunchRequest(bottle: bottle, executable: "C:\\g.exe", arguments: ["-user"]))
        #expect(plan.arguments == ["C:\\g.exe", "-a", "-b", "-user"])
    }

    @Test func noProfileMeansNoExtraArguments() throws {
        try installRuntime()
        let bottle = try BottleStore(paths: home.paths).create(name: "b")
        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: []))
        let plan = try launcher.plan(LaunchRequest(bottle: bottle, executable: "C:\\x.exe", arguments: ["-user"]))
        #expect(plan.arguments == ["C:\\x.exe", "-user"])
    }

    @Test func profilesWithoutLaunchArgumentsStillDecode() throws {
        let p = try JSONDecoder().decode(GameProfile.self, from: Data(#"{"id":"x","name":"X"}"#.utf8))
        #expect(p.launchArguments.isEmpty)
    }

    @Test func builtinSteamProfileDisablesCEFGPUAndMatchesSteamExe() throws {
        let steam = try #require(ProfileLibrary.load(paths: home.paths).match(executable: "C:\\Program Files (x86)\\Steam\\Steam.exe"))
        #expect(steam.id == "steam")
        #expect(steam.launchArguments == ["-cef-disable-gpu"])
    }
}

@Suite struct SteamLaunchTests {
    @Test func runGameURL() {
        #expect(SteamLibrary.runGameURL(appID: 3480990) == "steam://rungameid/3480990")
        #expect(SteamLibrary.runGameURL(appID: 0) == nil)
        #expect(SteamLibrary.runGameURL(appID: -1) == nil)
    }

    @Test func defaultExecutablePathMatchesSteamProfile() throws {
        let home = TempHome()
        let match = ProfileLibrary.load(paths: home.paths).match(executable: SteamLibrary.defaultExecutableInBottle)
        #expect(match?.id == "steam")
    }
}
