import Foundation
import Observation
import Sparkle

/// Sparkle updates. Only active inside a Tether.app that was built with an update signing key;
/// `swift run` and unsigned builds get a disabled "Check for Updates…" instead of Sparkle errors.
///
/// Sparkle installs an update only if its EdDSA signature matches the public key in Info.plist, so
/// the feed's host (or a redirect) can't push code the key holder didn't sign.
@MainActor
@Observable
final class Updater {
    /// Why updates can't run in this build, or nil if they can.
    nonisolated static var unavailableReason: String? {
        guard AppInfo.isBundledApp else { return "not running from Tether.app" }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty else {
            return "this build has no update signing key"
        }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String, !feed.isEmpty else {
            return "this build has no update feed"
        }
        return nil
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private let delegate = UpdaterDelegate()

    let isAvailable: Bool
    let unavailableMessage: String?

    var automaticallyChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    init() {
        let reason = Self.unavailableReason
        unavailableMessage = reason
        isAvailable = reason == nil
        let controller = reason == nil
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)
            : nil
        self.controller = controller
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }
}

/// Lets a test build point at a local feed (`TETHER_FEED_URL`); production builds use Info.plist.
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["TETHER_FEED_URL"]
    }
}
