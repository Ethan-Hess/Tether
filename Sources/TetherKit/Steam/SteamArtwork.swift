import Foundation

/// Fetches and caches a game's header image from Steam's public CDN.
///
/// Only app IDs of games installed in a bottle are ever requested. Downloads are https only,
/// size-capped, checked to be a real JPEG or PNG, and moved into the cache atomically. Nothing
/// else about the user or their library is sent.
public struct SteamArtwork: Sendable {
    public static let maxBytes = 2 * 1024 * 1024
    /// How long a "no art for this game" answer is remembered before asking again.
    public static let missingRetry: TimeInterval = 24 * 3600

    public let paths: TetherPaths
    public let download: RuntimeDownloader

    public init(paths: TetherPaths = .default, download: @escaping RuntimeDownloader = RuntimeInstaller.urlSessionDownload) {
        self.paths = paths
        self.download = download
    }

    public var directory: URL { paths.cache.appendingPathComponent("steam-art", isDirectory: true) }

    public static func url(appID: Int) -> URL? {
        guard appID > 0 else { return nil }
        return URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/header.jpg")
    }

    private func file(_ appID: Int) -> URL { directory.appendingPathComponent("\(appID).jpg") }
    private func marker(_ appID: Int) -> URL { directory.appendingPathComponent("\(appID).missing") }

    public func cachedFile(appID: Int) -> URL? {
        guard appID > 0, FileManager.default.fileExists(atPath: file(appID).path) else { return nil }
        return file(appID)
    }

    /// The cached image, downloading it first if needed. Nil when there is none (offline, no art
    /// for this game, or a response that failed validation).
    public func fetch(appID: Int) async -> URL? {
        guard let source = Self.url(appID: appID) else { return nil }
        if let cached = cachedFile(appID: appID) { return cached }
        if recentlyMissing(appID) { return nil }

        let fm = FileManager.default
        let downloaded: URL
        do {
            downloaded = try await download(source)
        } catch let error as URLError where error.code == .badServerResponse {
            remember(missing: appID) // the CDN answered "no": don't ask again today
            return nil
        } catch {
            return nil // offline or transient: try again next time
        }
        defer { try? fm.removeItem(at: downloaded) }

        guard Self.isAcceptableImage(downloaded) else {
            remember(missing: appID)
            return nil
        }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = file(appID)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: downloaded, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    static func isAcceptableImage(_ url: URL) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size > 8, size <= maxBytes,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        let bytes = [UInt8](head)
        let jpeg = bytes.starts(with: [0xFF, 0xD8, 0xFF])
        let png = bytes == [0x89, 0x50, 0x4E, 0x47]
        return jpeg || png
    }

    private func recentlyMissing(_ appID: Int) -> Bool {
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: marker(appID).path))?[.modificationDate] as? Date
        else { return false }
        return Date().timeIntervalSince(modified) < Self.missingRetry
    }

    private func remember(missing appID: Int) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data().write(to: marker(appID))
    }
}
