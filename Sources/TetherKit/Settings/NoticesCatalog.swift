import Foundation

/// A third-party component Tether ships or depends on, with its licence and where to get its source.
public struct NoticeComponent: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// "Tether", "Updates", "Runtime engine" or "Runtime libraries".
    public var group: String
    public var version: String?
    /// SPDX expression.
    public var license: String
    /// Files in `Notices/licenses`, shown in order.
    public var licenseFiles: [String]
    public var sourceURL: URL
    /// How the licence was established.
    public var basis: String
    /// False when the licence still rests on package metadata rather than a file from the source.
    public var verified: Bool
    public var note: String?
}

/// The notices shown in the app (and shipped as files in `Contents/Resources/Notices`). The
/// inventory and its caveats are also written up in `docs/THIRD-PARTY.md`.
public struct NoticesCatalog: Codable, Sendable {
    public var components: [NoticeComponent]

    public init(components: [NoticeComponent]) {
        self.components = components
    }

    public static func bundled() -> NoticesCatalog {
        guard let url = TetherResources.kitURL(forResource: "components", withExtension: "json", subdirectory: "Notices"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(NoticesCatalog.self, from: data)
        else {
            TetherLog.runtime.error("notices catalog missing or unreadable")
            return NoticesCatalog(components: [])
        }
        return catalog
    }

    /// The text of a licence file, or nil if it isn't bundled.
    public static func licenseText(file: String) -> String? {
        // Only plain file names: nothing from the catalog can point outside the licenses folder.
        guard !file.isEmpty, !file.contains("/"), !file.contains("..") else { return nil }
        guard let url = TetherResources.kitURL(forResource: file, subdirectory: "Notices/licenses"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public var groups: [String] {
        var seen: [String] = []
        for c in components where !seen.contains(c.group) { seen.append(c.group) }
        return seen
    }
}
