import Foundation
import Testing
@testable import TetherKit

@Suite struct BottleMigratorTests {
    let home = TempHome()

    /// A fake format 2 that renames `windowsVersion` to `winVer` and adds a flag, then a 3 that adds another.
    private let migrator = BottleMigrator(currentVersion: 3, steps: [
        1: { json in
            json["winVer"] = json.removeValue(forKey: "windowsVersion")
            json["flag"] = true
        },
        2: { json in json["extra"] = "x" },
    ])

    private func data(_ version: Int, extra: [String: Any] = [:]) throws -> Data {
        var json: [String: Any] = ["schemaVersion": version, "windowsVersion": "win10"]
        json.merge(extra) { _, new in new }
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func runsEveryStepFromTheStoredVersion() throws {
        let result = try #require(try migrator.migrate(try data(1)))
        #expect(result.from == 1)
        let json = try object(result.data)
        #expect(json["schemaVersion"] as? Int == 3)
        #expect(json["winVer"] as? String == "win10" && json["windowsVersion"] == nil)
        #expect(json["flag"] as? Bool == true && json["extra"] as? String == "x")
    }

    @Test func startsPartWayThrough() throws {
        let result = try #require(try migrator.migrate(try data(2)))
        let json = try object(result.data)
        #expect(json["windowsVersion"] as? String == "win10", "step 1 must not run again")
        #expect(json["extra"] as? String == "x")
    }

    @Test func currentFilesAreLeftAlone() throws {
        #expect(try migrator.migrate(try data(3)) == nil)
    }

    @Test func aNewerFileIsRefusedNotTruncated() throws {
        #expect(throws: BottleMigrationError.newerThanSupported(found: 4, supported: 3)) { try migrator.migrate(try data(4)) }
    }

    @Test func unreadableFilesAreReported() {
        #expect(throws: BottleMigrationError.self) { try migrator.migrate(Data("nope".utf8)) }
        #expect(throws: BottleMigrationError.self) { try migrator.migrate(Data("[1,2]".utf8)) }
        #expect(throws: BottleMigrationError.self) { try migrator.migrate(Data("{}".utf8)) }
    }

    @Test func aMissingStepIsAnErrorNotASilentSkip() throws {
        let gap = BottleMigrator(currentVersion: 3, steps: [2: { _ in }])
        #expect(throws: BottleMigrationError.stepFailed(from: 1, reason: "no upgrade step")) { try gap.migrate(try data(1)) }
    }

    @Test func aFailingStepProducesNothing() throws {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }
        let failing = BottleMigrator(currentVersion: 2, steps: [1: { _ in throw Boom() }])
        #expect(throws: BottleMigrationError.stepFailed(from: 1, reason: "boom")) { try failing.migrate(try data(1)) }
    }

    // MARK: through the store

    private func writeBottle(_ name: String, version: Int) throws -> URL {
        let root = home.paths.bottles.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let json: [String: Any] = [
            "schemaVersion": version, "windowsVersion": "win10", "environment": [String: String](),
            "showPerformanceHUD": false, "createdAt": "2026-01-01T00:00:00Z",
        ]
        let file = root.appendingPathComponent("bottle.json")
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        return file
    }

    @Test func loadUpgradesTheFileAndKeepsABackup() throws {
        let file = try writeBottle("old", version: 1)
        let original = try Data(contentsOf: file)
        let upgrade = BottleMigrator(currentVersion: 2, steps: [1: { json in json["showPerformanceHUD"] = true }])
        let bottle = try BottleStore(paths: home.paths, migrator: upgrade).load(name: "old")
        #expect(bottle.config.showPerformanceHUD)
        #expect(bottle.config.schemaVersion == 2)
        let backup = file.deletingLastPathComponent().appendingPathComponent("bottle.json.v1.bak")
        #expect(try Data(contentsOf: backup) == original)
        // The upgraded file is what's on disk now, and loading again doesn't migrate twice.
        #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) is [String: Any])
        #expect(try BottleStore(paths: home.paths, migrator: upgrade).load(name: "old").config.schemaVersion == 2)
    }

    @Test func aFailedUpgradeLeavesTheOriginalAndNoBackup() throws {
        let file = try writeBottle("keep", version: 1)
        let original = try Data(contentsOf: file)
        struct Boom: Error {}
        let failing = BottleMigrator(currentVersion: 2, steps: [1: { _ in throw Boom() }])
        #expect(throws: BottleMigrationError.self) { try BottleStore(paths: home.paths, migrator: failing).load(name: "keep") }
        #expect(try Data(contentsOf: file) == original)
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().appendingPathComponent("bottle.json.v1.bak").path))
    }

    @Test func listShowsUnreadableBottlesAsProblemsInsteadOfHidingThem() throws {
        _ = try writeBottle("fine", version: BottleConfig.currentSchemaVersion)
        _ = try writeBottle("future", version: BottleConfig.currentSchemaVersion + 5)
        let bad = home.paths.bottles.appendingPathComponent("broken")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("{{{".utf8).write(to: bad.appendingPathComponent("bottle.json"))
        try FileManager.default.createDirectory(at: home.paths.bottles.appendingPathComponent("not-a-bottle"), withIntermediateDirectories: true)

        let result = try BottleStore(paths: home.paths).listWithProblems()
        #expect(result.bottles.map(\.name) == ["fine"])
        #expect(result.problems.map(\.name) == ["broken", "future"])
        #expect(result.problems.first { $0.name == "future" }?.message.contains("newer version") == true)
        #expect(try BottleStore(paths: home.paths).list().map(\.name) == ["fine"])
    }
}
