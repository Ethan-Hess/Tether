import Foundation
import Testing
@testable import TetherKit

@Suite struct BottleStoreTests {
    let home = TempHome()
    var store: BottleStore { BottleStore(paths: home.paths) }

    @Test func createLoadRoundTrip() throws {
        let created = try store.create(name: "Overwatch", config: BottleConfig(backend: .dxmt, profileID: "overwatch"))
        let loaded = try store.load(name: "Overwatch")
        #expect(loaded.config.backend == .dxmt)
        #expect(loaded.config.profileID == "overwatch")
        #expect(created.prefixURL == loaded.prefixURL)
        #expect(FileManager.default.fileExists(atPath: loaded.prefixURL.path))
        #expect(try store.list().map(\.name) == ["Overwatch"])
    }

    @Test func duplicateNameRejected() throws {
        try store.create(name: "a")
        #expect(throws: BottleStoreError.alreadyExists("a")) { try store.create(name: "a") }
    }

    @Test(arguments: ["", "../x", "a/b", ".hidden"])
    func invalidNamesRejected(name: String) {
        #expect(throws: BottleStoreError.self) { try store.create(name: name) }
    }

    @Test func delete() throws {
        try store.create(name: "gone")
        try store.delete(name: "gone")
        #expect(try store.list().isEmpty)
        #expect(throws: BottleStoreError.notFound("gone")) { try store.delete(name: "gone") }
    }
}

@Suite struct BottleStoreManagementTests {
    let home = TempHome()
    var store: BottleStore { BottleStore(paths: home.paths) }

    @Test func renameMovesTheBottleAndKeepsConfig() throws {
        try store.create(name: "old", config: BottleConfig(profileID: "steam"))
        let renamed = try store.rename(from: "old", to: "new")
        #expect(renamed.name == "new")
        #expect(renamed.config.profileID == "steam")
        #expect(try store.list().map(\.name) == ["new"])
    }

    @Test func renameRejectsTakenAndInvalidNames() throws {
        try store.create(name: "a")
        try store.create(name: "b")
        #expect(throws: BottleStoreError.alreadyExists("b")) { try store.rename(from: "a", to: "b") }
        #expect(throws: BottleStoreError.self) { try store.rename(from: "a", to: "../evil") }
        #expect(throws: BottleStoreError.notFound("zzz")) { try store.rename(from: "zzz", to: "c") }
        #expect(try store.list().map(\.name) == ["a", "b"])
    }

    @Test func duplicateCopiesFilesAndLeavesTheOriginal() throws {
        let original = try store.create(name: "src")
        try Data("x".utf8).write(to: original.prefixURL.appendingPathComponent("marker"))
        let copy = try store.duplicate(name: "src", as: "dst")
        #expect(FileManager.default.fileExists(atPath: copy.prefixURL.appendingPathComponent("marker").path))
        #expect(try store.list().map(\.name) == ["dst", "src"])
        #expect(throws: BottleStoreError.alreadyExists("dst")) { try store.duplicate(name: "src", as: "dst") }
    }
}
