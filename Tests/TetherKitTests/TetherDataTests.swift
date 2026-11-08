import Foundation
import Testing
@testable import TetherKit

@Suite struct TetherDataTests {
    let home = TempHome()
    var fm: FileManager { .default }

    /// A data folder with something in every category.
    private func populate() throws {
        for dir in [home.paths.bottles.appendingPathComponent("Steam/prefix"), home.paths.runtimes.appendingPathComponent("0.2.0"),
                    home.paths.userComponents.appendingPathComponent("d3dmetal"), home.paths.cache.appendingPathComponent("steam-art"),
                    home.paths.profiles] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 50_000).write(to: dir.appendingPathComponent("file"))
        }
        try Data("{}".utf8).write(to: home.paths.settings)
    }

    private func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    @Test func summaryCountsEachCategory() throws {
        try populate()
        let s = TetherData.summary(paths: home.paths)
        #expect(s[.bottles]! >= 50_000 && s[.runtimes]! >= 100_000 && s[.cache]! >= 50_000 && s[.settings]! >= 50_000)
        #expect(TetherData.summary(paths: TetherPaths(root: home.root.appendingPathComponent("nothing"))).values.allSatisfy { $0 == 0 })
    }

    @Test func removesOnlyTheChosenCategories() throws {
        try populate()
        let removed = try TetherData.remove([.cache], paths: home.paths)
        #expect(removed.map(\.lastPathComponent) == ["Cache"])
        #expect(!exists(home.paths.cache))
        #expect(exists(home.paths.bottles) && exists(home.paths.runtimes) && exists(home.paths.settings))
    }

    @Test func removingEverythingAlsoRemovesAnEmptyRoot() throws {
        try populate()
        try TetherData.remove(Set(TetherDataCategory.allCases), paths: home.paths)
        #expect(!exists(home.paths.root))
    }

    @Test func aRootWithOtherFilesIsLeftInPlace() throws {
        try populate()
        try Data("mine".utf8).write(to: home.paths.root.appendingPathComponent("notes.txt"))
        try TetherData.remove(Set(TetherDataCategory.allCases), paths: home.paths)
        #expect(exists(home.paths.root.appendingPathComponent("notes.txt")))
        #expect(!exists(home.paths.bottles))
    }

    @Test func unknownFilesNextToOurFoldersSurviveEvenWhenRemovingEverything() throws {
        try populate()
        let other = home.paths.root.appendingPathComponent("Other")
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        try TetherData.remove(Set(TetherDataCategory.allCases), paths: home.paths)
        #expect(exists(other))
    }

    @Test func aLinkIsRemovedButItsTargetIsNotFollowed() throws {
        try fm.createDirectory(at: home.paths.root, withIntermediateDirectories: true)
        let outside = home.root.appendingPathComponent("outside-the-data-folder")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("precious".utf8).write(to: outside.appendingPathComponent("keep.txt"))
        try fm.createSymbolicLink(at: home.paths.bottles, withDestinationURL: outside)
        try TetherData.remove([.bottles], paths: home.paths)
        #expect(!exists(home.paths.bottles))
        #expect(exists(outside.appendingPathComponent("keep.txt")), "the folder the link pointed to must be untouched")
    }

    @Test func missingFoldersAreNotAnError() throws {
        try fm.createDirectory(at: home.paths.root, withIntermediateDirectories: true)
        #expect(try TetherData.remove(Set(TetherDataCategory.allCases), paths: home.paths).isEmpty)
    }

    @Test func dangerousRootsAreRefused() throws {
        for path in ["/", "/Users", NSHomeDirectory(), "/tmp"] {
            #expect(throws: TetherDataError.unsafeRoot(URL(fileURLWithPath: path).standardizedFileURL.path)) {
                try TetherData.remove([.bottles], paths: TetherPaths(root: URL(fileURLWithPath: path)))
            }
        }
    }
}
