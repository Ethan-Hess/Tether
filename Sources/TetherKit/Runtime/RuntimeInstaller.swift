import CryptoKit
import Foundation

public enum RuntimeInstallError: Error, LocalizedError, Equatable {
    case alreadyInstalled(String)
    case unsupportedURL(String)
    case unsupportedOS(required: String, current: String)
    case hashMismatch(expected: String, actual: String)
    case unsafeArchiveEntry(String)
    case extractionFailed(String)
    case missingBinary(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyInstalled(let v): return "Runtime \(v) is already installed."
        case .unsupportedURL(let u): return "Refusing to download from \(u): only https URLs are allowed."
        case .unsupportedOS(let required, let current): return "This runtime needs macOS \(required) or newer (this Mac has \(current))."
        case .hashMismatch(let expected, let actual): return "Download failed verification: expected SHA-256 \(expected) but got \(actual). Nothing was installed."
        case .unsafeArchiveEntry(let e): return "The archive contains an unsafe path (\(e)). Nothing was installed."
        case .extractionFailed(let m): return "Could not unpack the runtime: \(m)"
        case .missingBinary(let p): return "The unpacked runtime has no \(p)."
        }
    }
}

/// Downloads a runtime archive and returns the local file. The caller deletes the file.
public typealias RuntimeDownloader = @Sendable (URL) async throws -> URL

/// Installs a pinned runtime into `Runtimes/<version>`: download, verify the pinned SHA-256,
/// unpack into a staging directory, write `runtime.json`, then move into place. Nothing is left
/// behind on failure, and an existing install is never overwritten.
public struct RuntimeInstaller: Sendable {
    public let paths: TetherPaths
    public let download: RuntimeDownloader
    public let osVersion: OperatingSystemVersion

    public init(
        paths: TetherPaths = .default,
        osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        download: @escaping RuntimeDownloader = RuntimeInstaller.urlSessionDownload
    ) {
        self.paths = paths
        self.osVersion = osVersion
        self.download = download
    }

    public static let urlSessionDownload: RuntimeDownloader = { url in
        let (file, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: file)
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) from \(url.host ?? "server")"])
        }
        return file
    }

    @discardableResult
    public func install(_ source: RuntimeSource) async throws -> WineRuntime {
        let fm = FileManager.default
        let destination = paths.runtimes.appendingPathComponent(source.version, isDirectory: true)
        if fm.fileExists(atPath: destination.path) { throw RuntimeInstallError.alreadyInstalled(source.version) }
        guard source.url.scheme == "https" else { throw RuntimeInstallError.unsupportedURL(source.url.absoluteString) }
        if let minimum = source.minimumMacOS, !Self.os(osVersion, isAtLeast: minimum) {
            throw RuntimeInstallError.unsupportedOS(
                required: minimum,
                current: "\(osVersion.majorVersion).\(osVersion.minorVersion)"
            )
        }

        try fm.createDirectory(at: paths.runtimes, withIntermediateDirectories: true)
        let archive = try await download(source.url)
        defer { try? fm.removeItem(at: archive) }

        let actual = try Self.sha256Hex(of: archive)
        guard actual == source.sha256.lowercased() else {
            throw RuntimeInstallError.hashMismatch(expected: source.sha256.lowercased(), actual: actual)
        }

        let staging = paths.runtimes.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try Self.validateEntries(of: archive)
            try Self.extract(archive, into: staging, stripComponents: source.stripComponents)
            let wine = staging.appendingPathComponent("bin/wine").path
            guard fm.isExecutableFile(atPath: wine) else { throw RuntimeInstallError.missingBinary("bin/wine") }
            let manifest = try JSONEncoder.pretty.encode(source.manifest)
            try manifest.write(to: staging.appendingPathComponent("runtime.json"))
            try fm.moveItem(at: staging, to: destination)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        TetherLog.runtime.info("Installed runtime \(source.version, privacy: .public)")
        return WineRuntime(root: destination, manifest: source.manifest)
    }

    // MARK: - helpers

    static func os(_ v: OperatingSystemVersion, isAtLeast minimum: String) -> Bool {
        let parts = minimum.split(separator: ".").compactMap { Int($0) }
        let required = OperatingSystemVersion(
            majorVersion: parts.first ?? 0,
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0
        )
        return (v.majorVersion, v.minorVersion, v.patchVersion) >= (required.majorVersion, required.minorVersion, required.patchVersion)
    }

    static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Rejects absolute paths and `..` components before anything is written.
    static func validateEntries(of archive: URL) throws {
        let listing = try runTar(["-tf", archive.path])
        for entry in listing.split(separator: "\n").map(String.init) {
            let components = entry.split(separator: "/", omittingEmptySubsequences: false)
            if entry.hasPrefix("/") || components.contains("..") {
                throw RuntimeInstallError.unsafeArchiveEntry(entry)
            }
        }
    }

    static func extract(_ archive: URL, into directory: URL, stripComponents: Int) throws {
        _ = try runTar(["-xf", archive.path, "-C", directory.path, "--strip-components", String(stripComponents), "--no-same-owner"])
    }

    @discardableResult
    private static func runTar(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.environment = ["PATH": "/usr/bin:/bin"]
        try process.run()
        // Drain both pipes before waiting so a large listing can't block the child.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw RuntimeInstallError.extractionFailed(message.isEmpty ? "tar exited with \(process.terminationStatus)" : message)
        }
        return String(decoding: outData, as: UTF8.self)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
