import Foundation
import os

public enum TetherLog {
    static let subsystem = "dev.tether"
    public static let launch = Logger(subsystem: subsystem, category: "launch")
    public static let profiles = Logger(subsystem: subsystem, category: "profiles")
    public static let runtime = Logger(subsystem: subsystem, category: "runtime")
}

/// Host checks surfaced by `tether doctor` and the app's first-run screen.
public struct SystemCheck: Sendable {
    public struct Item: Sendable {
        public let name: String
        public let ok: Bool
        public let detail: String
    }

    public let items: [Item]

    public static func run(paths: TetherPaths = .default) -> SystemCheck {
        let fm = FileManager.default
        var items: [Item] = []

        #if arch(arm64)
        items.append(Item(name: "Apple Silicon", ok: true, detail: "arm64"))
        #else
        items.append(Item(name: "Apple Silicon", ok: false, detail: "Intel Macs are not a target platform"))
        #endif

        let v = ProcessInfo.processInfo.operatingSystemVersion
        items.append(Item(name: "macOS ≥ 14", ok: v.majorVersion >= 14, detail: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"))

        // The arm64 + FEX runtime needs the cross-architecture entitlement path (ADR 0005).
        let canRunGames = RuntimeInstaller.os(v, isAtLeast: "26.4")
        items.append(Item(
            name: "macOS ≥ 26.4 (to run games)",
            ok: canRunGames,
            detail: canRunGames ? "ok" : "the app works, but the Wine runtime needs macOS 26.4 or newer"
        ))

        let runtimes = RuntimeStore(paths: paths).list()
        items.append(Item(
            name: "Wine runtime",
            ok: !runtimes.isEmpty,
            detail: runtimes.isEmpty ? "none installed (run: tether runtime install)" : runtimes.map(\.version).joined(separator: ", ")
        ))

        let gptk = fm.fileExists(atPath: paths.userComponents.appendingPathComponent("d3dmetal").path)
        items.append(Item(name: "D3DMetal (optional)", ok: true, detail: gptk ? "imported" : "not imported (optional; needed for D3D12)"))

        return SystemCheck(items: items)
    }
}
