import Foundation
@testable import TetherKit

/// A throwaway `TETHER_HOME` per test.
final class TempHome {
    let root: URL
    let paths: TetherPaths

    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tether-tests-\(UUID().uuidString)")
        paths = TetherPaths(root: root)
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}
