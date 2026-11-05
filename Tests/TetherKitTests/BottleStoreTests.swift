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
