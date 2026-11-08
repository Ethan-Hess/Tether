import Foundation
import Testing
@testable import TetherKit

@Suite struct NoticesTests {
    let catalog = NoticesCatalog.bundled()

    @Test func theCatalogLoads() {
        #expect(catalog.components.count >= 20)
        #expect(Set(catalog.components.map(\.id)).count == catalog.components.count, "ids must be unique")
        #expect(catalog.groups.first == "Tether")
    }

    @Test func everyComponentHasALicenceTextAndAnHTTPSSource() {
        for c in catalog.components {
            #expect(!c.licenseFiles.isEmpty, "\(c.name) has no licence file")
            for file in c.licenseFiles {
                #expect((NoticesCatalog.licenseText(file: file) ?? "").count > 200, "\(c.name): \(file) is missing or too short")
            }
            #expect(c.sourceURL.scheme == "https", "\(c.name) needs an https source link")
            #expect(!c.license.isEmpty && !c.basis.isEmpty)
        }
    }

    @Test func everyLicenceFileIsUsedAndNothingSneaksOutOfTheFolder() throws {
        let used = Set(catalog.components.flatMap(\.licenseFiles))
        let dir = try #require(TetherResources.kitURL(forResource: "licenses", subdirectory: "Notices"))
        let onDisk = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        #expect(onDisk == used, "unused or missing licence files: \(onDisk.symmetricDifference(used))")
        #expect(NoticesCatalog.licenseText(file: "../components.json") == nil)
        #expect(NoticesCatalog.licenseText(file: "a/b") == nil)
        #expect(NoticesCatalog.licenseText(file: "") == nil)
    }

    @Test func unverifiedRowsAreHonestlyLabelled() {
        let unverified = catalog.components.filter { !$0.verified }
        #expect(!unverified.isEmpty, "this list should shrink as rows are checked against sources")
        #expect(unverified.allSatisfy { $0.basis.localizedCaseInsensitiveContains("not checked") || $0.basis.localizedCaseInsensitiveContains("metadata") })
        #expect(catalog.components.filter(\.verified).allSatisfy { !$0.basis.localizedCaseInsensitiveContains("not checked") })
    }

    @Test func theRuntimeEngineAndItsSourceAreListed() throws {
        let wine = try #require(catalog.components.first { $0.id == "wine" })
        #expect(wine.note?.contains("arm64-11.20-5") == true, "the LGPL source for the shipped build must be linked")
        for id in ["mach9", "fex", "dxmt", "mesa", "tether", "sparkle"] {
            #expect(catalog.components.contains { $0.id == id }, "\(id) missing")
        }
    }
}
