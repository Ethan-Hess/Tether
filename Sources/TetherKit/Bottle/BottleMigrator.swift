import Foundation

public enum BottleMigrationError: Error, LocalizedError, Equatable {
    /// `bottle.json` was written by a newer Tether. Opening it with this version could drop settings.
    case newerThanSupported(found: Int, supported: Int)
    case unreadable(String)
    case stepFailed(from: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case .newerThanSupported(let found, let supported):
            return "This bottle was made by a newer version of Tether (settings format \(found); this version understands up to \(supported)). Update Tether to open it."
        case .unreadable(let why): return "The bottle's settings file can't be read: \(why)"
        case .stepFailed(let from, let reason): return "Couldn't upgrade the bottle's settings from format \(from): \(reason)"
        }
    }
}

/// Upgrades an older `bottle.json` to the current format, one version at a time.
///
/// Works on the file's JSON before it is decoded, so a field added, renamed or restructured by a
/// later version is handled in one place. Steps are keyed by the version they upgrade *from*.
public struct BottleMigrator: Sendable {
    public typealias Step = @Sendable (inout [String: Any]) throws -> Void

    public let currentVersion: Int
    public let steps: [Int: Step]

    /// No steps yet: format 1 is the only one released. Add `1: { json in … }` when 2 exists.
    public static let standard = BottleMigrator(currentVersion: BottleConfig.currentSchemaVersion, steps: [:])

    public init(currentVersion: Int, steps: [Int: Step]) {
        self.currentVersion = currentVersion
        self.steps = steps
    }

    /// The upgraded file contents and the version they came from, or nil if already current.
    /// Throws without producing anything if the file is newer, unreadable, or a step fails.
    public func migrate(_ data: Data) throws -> (data: Data, from: Int)? {
        guard var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw BottleMigrationError.unreadable("not a JSON object")
        }
        guard let version = json["schemaVersion"] as? Int else {
            throw BottleMigrationError.unreadable("no schemaVersion")
        }
        if version > currentVersion { throw BottleMigrationError.newerThanSupported(found: version, supported: currentVersion) }
        if version == currentVersion { return nil }
        var v = version
        while v < currentVersion {
            guard let step = steps[v] else { throw BottleMigrationError.stepFailed(from: v, reason: "no upgrade step") }
            do { try step(&json) } catch { throw BottleMigrationError.stepFailed(from: v, reason: error.localizedDescription) }
            v += 1
            json["schemaVersion"] = v
        }
        let out = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        return (out, version)
    }
}
