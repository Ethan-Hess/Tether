import CryptoKit
import Foundation
import Testing
@testable import TetherKit

@Suite struct RuntimeInstallerTests {
    let home = TempHome()
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("tether-installer-\(UUID().uuidString)")

    // MARK: fixtures

    /// Builds `<name>.tar.xz` containing `top/bin/wine` (executable) and `top/lib/x`, plus any extra files.
    func makeArchive(top: String = "wine", withWine: Bool = true, extra: [String: String] = [:]) throws -> URL {
        let fm = FileManager.default
        let tree = work.appendingPathComponent("tree-\(UUID().uuidString)")
        let bin = tree.appendingPathComponent("\(top)/bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        if withWine {
            let wine = bin.appendingPathComponent("wine")
            try "#!/bin/sh\n".write(to: wine, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        }
        try fm.createDirectory(at: tree.appendingPathComponent("\(top)/lib"), withIntermediateDirectories: true)
        try "x".write(to: tree.appendingPathComponent("\(top)/lib/x"), atomically: true, encoding: .utf8)
        for (path, body) in extra {
            let url = tree.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url, atomically: true, encoding: .utf8)
        }
        let archive = work.appendingPathComponent("a-\(UUID().uuidString).tar.xz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-cJf", archive.path, "-C", tree.path, "."]
        try tar.run()
        tar.waitUntilExit()
        #expect(tar.terminationStatus == 0)
        return archive
    }

    func sha(_ url: URL) throws -> String { try RuntimeInstaller.sha256Hex(of: url) }

    func source(sha256: String, version: String = "9.9.9", strip: Int = 2, minimumMacOS: String? = nil) -> RuntimeSource {
        RuntimeSource(
            version: version, wineVersion: "1.0", features: ["msync"],
            components: [.init(name: "wine", version: "1.0", source: nil)],
            url: URL(string: "https://example.invalid/runtime.tar.xz")!,
            sha256: sha256, size: 1, stripComponents: strip, minimumMacOS: minimumMacOS
        )
    }

    func installer(serving archive: URL, os: OperatingSystemVersion = .init(majorVersion: 26, minorVersion: 6, patchVersion: 2)) -> RuntimeInstaller {
        RuntimeInstaller(paths: home.paths, osVersion: os) { _ in
            // The installer deletes what it downloads, so hand it a copy.
            let copy = archive.deletingLastPathComponent().appendingPathComponent("dl-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: archive, to: copy)
            return copy
        }
    }

    func leftovers() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: home.paths.runtimes.path)) ?? [])
    }

    // MARK: tests

    @Test func installsVerifiesAndIsResolvable() async throws {
        let archive = try makeArchive()
        let runtime = try await installer(serving: archive).install(source(sha256: try sha(archive)))

        #expect(FileManager.default.isExecutableFile(atPath: runtime.wineBinary.path))
        #expect(FileManager.default.fileExists(atPath: runtime.root.appendingPathComponent("lib/x").path))
        // The store sees it, with the manifest the installer wrote.
        let resolved = try RuntimeStore(paths: home.paths).resolve(version: nil)
        #expect(resolved.version == "9.9.9")
        #expect(resolved.supports(feature: "msync"))
        #expect(leftovers() == ["9.9.9"])
    }

    @Test func hashMismatchInstallsNothing() async throws {
        let archive = try makeArchive()
        await #expect(throws: RuntimeInstallError.self) {
            try await installer(serving: archive).install(source(sha256: String(repeating: "0", count: 64)))
        }
        #expect(leftovers().isEmpty)
    }

    @Test func existingInstallIsNotOverwritten() async throws {
        let archive = try makeArchive()
        let s = source(sha256: try sha(archive))
        let i = installer(serving: archive)
        try await i.install(s)
        await #expect(throws: RuntimeInstallError.alreadyInstalled("9.9.9")) { try await i.install(s) }
    }

    @Test func nonHTTPSURLRejected() async throws {
        var s = source(sha256: String(repeating: "0", count: 64))
        s.url = URL(string: "http://example.invalid/runtime.tar.xz")!
        let archive = try makeArchive()
        await #expect(throws: RuntimeInstallError.self) { try await installer(serving: archive).install(s) }
        #expect(leftovers().isEmpty)
    }

    @Test func tooOldMacOSRejectedBeforeDownload() async throws {
        let s = source(sha256: String(repeating: "0", count: 64), minimumMacOS: "26.4")
        let old = OperatingSystemVersion(majorVersion: 26, minorVersion: 3, patchVersion: 0)
        let i = RuntimeInstaller(paths: home.paths, osVersion: old) { _ in
            Issue.record("should not download on an unsupported OS")
            throw URLError(.cancelled)
        }
        await #expect(throws: RuntimeInstallError.unsupportedOS(required: "26.4", current: "26.3")) { try await i.install(s) }
    }

    @Test func archiveWithoutWineBinaryRejectedAndCleanedUp() async throws {
        let archive = try makeArchive(withWine: false)
        await #expect(throws: RuntimeInstallError.missingBinary("bin/wine")) {
            try await installer(serving: archive).install(source(sha256: try sha(archive), strip: 2))
        }
        #expect(leftovers().isEmpty)
    }

    @Test func pathTraversalEntryRejected() throws {
        // Build a tar that contains "../escape" using bsdtar's -P (keep leading ../ paths).
        let fm = FileManager.default
        let base = work.appendingPathComponent("trav")
        let inner = base.appendingPathComponent("inner")
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)
        try "x".write(to: base.appendingPathComponent("escape"), atomically: true, encoding: .utf8)
        let archive = work.appendingPathComponent("trav.tar")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.currentDirectoryURL = inner
        tar.arguments = ["-P", "-cf", archive.path, "../escape"]
        try tar.run()
        tar.waitUntilExit()
        #expect(tar.terminationStatus == 0)
        #expect(throws: RuntimeInstallError.unsafeArchiveEntry("../escape")) {
            try RuntimeInstaller.validateEntries(of: archive)
        }
    }

    @Test func osVersionComparison() {
        let v = OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
        #expect(RuntimeInstaller.os(v, isAtLeast: "26.4"))
        #expect(RuntimeInstaller.os(v, isAtLeast: "26"))
        #expect(!RuntimeInstaller.os(v, isAtLeast: "26.4.1"))
        #expect(!RuntimeInstaller.os(v, isAtLeast: "27"))
    }

    @Test func bundledCatalogIsWellFormed() {
        let catalog = RuntimeCatalog.bundled()
        #expect(!catalog.runtimes.isEmpty)
        for r in catalog.runtimes {
            #expect(r.url.scheme == "https")
            #expect(r.sha256.count == 64 && r.sha256.allSatisfy(\.isHexDigit))
            #expect(r.features.contains("msync"))
        }
        #expect(catalog.source(version: nil) != nil)
        #expect(catalog.source(version: "no-such-version") == nil)
    }
}
