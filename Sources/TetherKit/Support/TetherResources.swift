import Foundation

/// Finds files bundled with Tether.
///
/// Inside Tether.app they live in `Contents/Resources`. SwiftPM's own `Bundle.module` can't be
/// used there: it looks for its resource bundle at the app's root (which also stops the app from
/// being signed) and otherwise at a path inside the build folder of the Mac that built it. So the
/// app's resources are looked up first, and `Bundle.module` is only the fallback for development
/// (`swift run`) and tests.
public enum TetherResources {
    /// `Contents/Resources` when running inside an `.app`, otherwise nil.
    public static var mainResources: URL? {
        Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.resourceURL : nil
    }

    public static func url(
        forResource name: String,
        withExtension ext: String? = nil,
        subdirectory: String? = nil,
        mainResources: URL? = TetherResources.mainResources,
        fallback: () -> URL? = { nil }
    ) -> URL? {
        if let base = mainResources {
            var candidate = base
            if let subdirectory { candidate.appendPathComponent(subdirectory, isDirectory: true) }
            candidate.appendPathComponent(ext.map { "\(name).\($0)" } ?? name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return fallback()
    }

    /// A resource of TetherKit itself: `Contents/Resources` in the app, `Bundle.module` otherwise.
    public static func kitURL(forResource name: String, withExtension ext: String? = nil, subdirectory: String? = nil) -> URL? {
        url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
        }
    }
}
