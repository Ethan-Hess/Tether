import Foundation

public enum SteamInstallError: Error, LocalizedError, Equatable {
    case unsupportedURL(String)
    case installerFailed(Int32)
    case steamNotFound

    public var errorDescription: String? {
        switch self {
        case .unsupportedURL(let u): return "Refusing to download from \(u): only https URLs are allowed."
        case .installerFailed(let c): return "The Steam installer exited with status \(c). See the bottle's logs/wine.log."
        case .steamNotFound: return "The installer finished but \(SteamLibrary.defaultExecutableInBottle) is missing."
        }
    }
}

/// Downloads Valve's `SteamSetup.exe` and runs it silently (`/S`) inside a bottle.
///
/// The installer is Valve's own file from their CDN, fetched over https. Its hash isn't pinned
/// because Valve updates it in place. This never handles credentials: the user logs in
/// inside Steam afterwards.
public struct SteamInstaller: Sendable {
    public static let installerURL = URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!

    public let launcher: Launcher
    public let source: URL
    public let download: RuntimeDownloader

    public init(
        launcher: Launcher = Launcher(),
        source: URL = SteamInstaller.installerURL,
        download: @escaping RuntimeDownloader = RuntimeInstaller.urlSessionDownload
    ) {
        self.launcher = launcher
        self.source = source
        self.download = download
    }

    public static func isInstalled(in bottle: Bottle) -> Bool {
        FileManager.default.fileExists(atPath: bottle.driveC.appendingPathComponent(SteamLibrary.defaultRootInBottle + "/Steam.exe").path)
    }

    public func install(into bottle: Bottle) async throws {
        guard source.scheme == "https" else { throw SteamInstallError.unsupportedURL(source.absoluteString) }
        let fm = FileManager.default

        let downloaded = try await download(source)
        // Wine runs the file from a plain, private directory with its real name.
        let workDir = fm.temporaryDirectory.appendingPathComponent("tether-steam-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: downloaded)
            try? fm.removeItem(at: workDir)
        }
        let setup = workDir.appendingPathComponent("SteamSetup.exe")
        try fm.moveItem(at: downloaded, to: setup)

        let launcher = self.launcher
        let status: Int32 = try await Task.detached {
            let plan = try launcher.plan(LaunchRequest(bottle: bottle, executable: setup.path, arguments: ["/S"]))
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                do {
                    try launcher.launch(plan) { continuation.resume(returning: $0) }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }.value

        guard status == 0 else { throw SteamInstallError.installerFailed(status) }
        guard Self.isInstalled(in: bottle) else { throw SteamInstallError.steamNotFound }
    }
}
