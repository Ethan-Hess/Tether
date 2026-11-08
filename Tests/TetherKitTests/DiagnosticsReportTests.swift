import Foundation
import Testing
@testable import TetherKit

@Suite struct DiagnosticsReportTests {
    let home = TempHome()

    private func report(env: [String: String] = [:], args: [String] = [], sessions: [LaunchLog.Session] = [], userHome: String = "/Users/someone") throws -> String {
        let bottle = try BottleStore(paths: home.paths).create(name: "b", config: BottleConfig(environment: env, launchArguments: args))
        return DiagnosticsReport.make(bottle: bottle, runtime: nil, system: SystemCheck(items: [.init(name: "Check", ok: true, detail: "fine")]), sessions: sessions, home: userHome)
    }

    @Test func leavesOutEnvironmentValuesAndArgumentContents() throws {
        let r = try report(env: ["MY_KEY": "super-secret-value"], args: ["-login", "user", "hunter2"])
        #expect(r.contains("MY_KEY"))
        #expect(!r.contains("super-secret-value"))
        #expect(!r.contains("hunter2"))
        #expect(r.contains("Launch arguments: 3"))
    }

    @Test func redactsTheHomeDirectory() throws {
        let s = LaunchLog.Session(id: 0, start: nil, executable: "x.exe", text: "loaded /Users/someone/Library/Application Support/Tether/Runtimes/0.2.0")
        let r = try report(sessions: [s])
        #expect(!r.contains("/Users/someone"))
        #expect(r.contains("~/Library/Application Support/Tether"))
    }

    @Test func keepsOnlyTheLastLinesOfTheLatestLaunch() throws {
        let text = (1...500).map { "line\($0)" }.joined(separator: "\n")
        let bottle = try BottleStore(paths: home.paths).create(name: "c")
        let r = DiagnosticsReport.make(
            bottle: bottle, runtime: nil, system: SystemCheck(items: []),
            sessions: [LaunchLog.Session(id: 0, start: nil, executable: "x.exe", text: text)], tailLines: 10
        )
        #expect(r.contains("line500") && r.contains("line491") && !r.contains("line490"))
    }

    @Test func saysSoWhenThereIsNoLog() throws {
        #expect(try report().contains("No log."))
    }
}
