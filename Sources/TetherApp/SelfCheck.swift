import Foundation
import TetherKit

/// `Tether --self-check`: prints what the running copy can find and exits, without opening a window.
/// Packaging uses it to prove that the built app locates its bundled resources and runtime.
enum SelfCheck {
    static func run() -> Never {
        let catalog = RuntimeCatalog.bundled().runtimes.count
        let profiles = ProfileLibrary.load().profiles.count
        let notices = NoticesCatalog.bundled().components.count
        let store = RuntimeStore()
        let runtime = try? store.resolve(version: nil)
        print("version=\(AppInfo.display)")
        print("bundle=\(Bundle.main.bundlePath)")
        // Where resources really come from: inside the app, or (in development) SwiftPM's bundle.
        print("resources=\(TetherResources.kitURL(forResource: "catalog", withExtension: "json", subdirectory: "Runtimes")?.deletingLastPathComponent().deletingLastPathComponent().path ?? "none")")
        print("catalog-runtimes=\(catalog)")
        print("profiles=\(profiles)")
        print("notices=\(notices)")
        print("embedded-root=\(store.embeddedRoot?.path ?? "none")")
        print("runtime=\(runtime.map { "\($0.version) embedded=\($0.isEmbedded)" } ?? "none")")
        print("updater=\(Updater.unavailableReason ?? "enabled")")
        exit(catalog > 0 && profiles > 0 && notices > 0 ? 0 : 1)
    }
}
