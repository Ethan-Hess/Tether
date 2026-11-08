import Foundation
import Testing
@testable import TetherKit

@Suite struct LaunchNoticesTests {
    let home = TempHome()

    @Test func protectedEnvironmentKeysAreReported() throws {
        let root = home.paths.runtimes.appendingPathComponent("0.1.0")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(RuntimeManifest(version: "0.1.0", wineVersion: "11", features: [], components: []))
            .write(to: root.appendingPathComponent("runtime.json"))
        let bottle = try BottleStore(paths: home.paths).create(name: "b", config: BottleConfig(environment: ["DYLD_INSERT_LIBRARIES": "x"]))
        let plan = try Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: [])).plan(LaunchRequest(bottle: bottle, executable: "C:\\a.exe"))
        let messages = LaunchNotices.messages(for: plan)
        #expect(messages.contains("warning: environment key 'DYLD_INSERT_LIBRARIES' is protected and was ignored"))
    }
}
