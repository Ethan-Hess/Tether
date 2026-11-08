import Foundation

/// Facts about the running app, from its Info.plist. Plain values when run with `swift run`.
enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    static var isBundledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    /// "0.1.0 (42)", or "development build" when not run from Tether.app.
    static var display: String { isBundledApp ? "\(version) (\(build))" : "development build" }
}
