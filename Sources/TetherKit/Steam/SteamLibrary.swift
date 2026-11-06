import Foundation

/// A game Steam reports as installed, read from `appmanifest_<appid>.acf`.
public struct SteamApp: Hashable, Sendable, Identifiable {
    public var id: Int { appID }
    public let appID: Int
    public let name: String
    /// Folder name under `steamapps/common`.
    public let installDir: String
    /// Host path of that folder.
    public let installURL: URL
    public let sizeOnDisk: Int64?
    public let lastUpdated: Date?
    public let buildID: String?
    public let stateFlags: Int?

    /// Steam's `StateFlags` bit 4 means fully installed. Unknown flags are treated as installed
    /// because older manifests omit them.
    public var isFullyInstalled: Bool { stateFlags.map { $0 & 4 != 0 } ?? true }
}

public enum SteamLibraryError: Error, Equatable, LocalizedError {
    case notAnAppManifest
    case invalidAppID(String)
    case unsafeInstallDir(String)

    public var errorDescription: String? {
        switch self {
        case .notAnAppManifest: return "Not a Steam app manifest (no AppState)."
        case .invalidAppID(let v): return "Invalid app id '\(v)'."
        case .unsafeInstallDir(let v): return "Install directory '\(v)' is not a plain folder name."
        }
    }
}

/// Reads Steam's library metadata. Everything here is read-only: it never runs or modifies Steam.
public enum SteamLibrary {
    /// Default Steam install location inside a bottle.
    public static let defaultRootInBottle = "Program Files (x86)/Steam"

    /// Largest manifest or library file we will read. Real files are far smaller.
    static let maxFileSize = 8 * 1024 * 1024

    /// Windows path of the Steam client inside a bottle.
    public static let defaultExecutableInBottle = "C:\\Program Files (x86)\\Steam\\Steam.exe"

    /// The URL that asks a running (or starting) Steam to launch a game, so Steamworks DRM,
    /// Cloud saves and achievements all work as they do on Windows.
    public static func runGameURL(appID: Int) -> String? {
        appID > 0 ? "steam://rungameid/\(appID)" : nil
    }

    // MARK: parsing

    /// Library folder paths exactly as written in `libraryfolders.vdf` (usually Windows paths).
    /// Handles both the current format (`"0" { "path" "…" … }`) and the older one (`"1" "D:\\…"`).
    public static func libraryFolders(vdf text: String) throws -> [String] {
        let doc = try KeyValues.parse(text)
        guard let root = doc["libraryfolders"] else { return [] }
        return root.entries.compactMap { entry -> String? in
            guard !entry.key.isEmpty, entry.key.allSatisfy(\.isNumber) else { return nil }
            switch entry.value {
            case .string(let path): return path
            case .object: return entry.value["path"]?.string
            }
        }
        .filter { !$0.isEmpty }
    }

    /// Parses one app manifest. `libraryRoot` is the host path of the library that contains it.
    public static func parseAppManifest(_ text: String, libraryRoot: URL) throws -> SteamApp {
        let doc = try KeyValues.parse(text)
        guard let state = doc["AppState"] else { throw SteamLibraryError.notAnAppManifest }

        let rawID = state["appid"]?.string ?? ""
        guard let appID = Int(rawID), appID > 0 else { throw SteamLibraryError.invalidAppID(rawID) }

        let installDir = state["installdir"]?.string ?? ""
        // The install dir is joined into a path, so it must be a single plain component.
        guard !installDir.isEmpty, installDir != ".", installDir != "..",
              !installDir.contains("/"), !installDir.contains("\\"), !installDir.contains("\0")
        else { throw SteamLibraryError.unsafeInstallDir(installDir) }

        let name = state["name"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? "App \(appID)"
        return SteamApp(
            appID: appID,
            name: name,
            installDir: installDir,
            installURL: libraryRoot.appendingPathComponent("steamapps/common/\(installDir)", isDirectory: true),
            sizeOnDisk: state["SizeOnDisk"]?.string.flatMap { Int64($0) },
            lastUpdated: state["LastUpdated"]?.string.flatMap { TimeInterval($0) }.map { Date(timeIntervalSince1970: $0) },
            buildID: state["buildid"]?.string,
            stateFlags: state["StateFlags"]?.string.flatMap { Int($0) }
        )
    }

    // MARK: scanning

    /// Lists installed games across Steam's library folders.
    ///
    /// - Parameters:
    ///   - steamRoot: host path of the Steam install (contains `steamapps/`).
    ///   - mapWindowsPath: converts a library path from `libraryfolders.vdf` to a host path.
    ///     Return nil for paths that don't exist or can't be mapped; they are skipped.
    /// Unreadable or malformed manifests are skipped (and logged), never fatal.
    public static func installedApps(steamRoot: URL, mapWindowsPath: (String) -> URL?) -> [SteamApp] {
        var libraries: [URL] = [steamRoot]
        if let text = readText(steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")),
           let paths = try? libraryFolders(vdf: text) {
            for path in paths {
                if let url = mapWindowsPath(path) { libraries.append(url) }
            }
        }

        var seenLibraries = Set<String>()
        var seenApps = Set<Int>()
        var apps: [SteamApp] = []
        for library in libraries {
            guard seenLibraries.insert(library.standardizedFileURL.path).inserted else { continue }
            let steamapps = library.appendingPathComponent("steamapps", isDirectory: true)
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: steamapps.path)) ?? []).sorted()
            for file in names where isAppManifestName(file) {
                guard let text = readText(steamapps.appendingPathComponent(file)) else { continue }
                do {
                    let app = try parseAppManifest(text, libraryRoot: library)
                    if seenApps.insert(app.appID).inserted { apps.append(app) }
                } catch {
                    TetherLog.profiles.error("Skipping \(file, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Lists installed games for a bottle's Steam install.
    public static func installedApps(in bottle: Bottle, steamRoot: URL? = nil) -> [SteamApp] {
        let root = steamRoot ?? bottle.driveC.appendingPathComponent(defaultRootInBottle, isDirectory: true)
        return installedApps(steamRoot: root, mapWindowsPath: { bottle.hostURL(forWindowsPath: $0) })
    }

    static func isAppManifestName(_ name: String) -> Bool {
        guard name.hasPrefix("appmanifest_"), name.hasSuffix(".acf") else { return false }
        let digits = name.dropFirst("appmanifest_".count).dropLast(".acf".count)
        return !digits.isEmpty && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber)
    }

    private static func readText(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size <= maxFileSize,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

public extension Bottle {
    /// Maps a Windows path inside this bottle (`C:\Program Files\…`, `D:/Games`) to a host path.
    ///
    /// `C:` is the bottle's `drive_c`; other letters follow the prefix's `dosdevices` symlinks.
    /// Returns nil for anything that isn't an absolute drive path, uses `..`, or has no such drive.
    func hostURL(forWindowsPath path: String) -> URL? {
        let chars = Array(path)
        guard chars.count >= 2, chars[0].isASCII, chars[0].isLetter, chars[1] == ":" else { return nil }
        let rest = String(chars.dropFirst(2))
        let components = rest.split(whereSeparator: { $0 == "\\" || $0 == "/" }).map(String.init)
        guard !components.contains("..") else { return nil }

        let letter = String(chars[0]).lowercased()
        let base: URL
        if letter == "c" {
            base = driveC
        } else {
            let link = prefixURL.appendingPathComponent("dosdevices/\(letter):")
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return nil }
            base = target.hasPrefix("/")
                ? URL(fileURLWithPath: target, isDirectory: true)
                : URL(fileURLWithPath: target, relativeTo: link.deletingLastPathComponent()).standardizedFileURL
        }
        return components.reduce(base) { $0.appendingPathComponent($1, isDirectory: true) }
    }
}
