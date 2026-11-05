import Foundation

/// Copies a backend's PE DLLs into a bottle's prefix.
///
/// Copies (rather than symlinks) so that the files Windows code sees are ordinary files
/// in system32/syswow64, exactly as on a Windows install.
public struct BackendInstaller: Sendable {
    public let paths: TetherPaths

    public init(paths: TetherPaths = .default) {
        self.paths = paths
    }

    public struct CopyStep: Hashable, Sendable {
        public let source: URL
        public let destination: URL
    }

    /// Pure planning step, unit-testable without touching the prefix.
    public func plan(backend: any GraphicsBackend, runtime: WineRuntime, bottle: Bottle) -> [CopyStep] {
        let src = backend.sourceDirectory(runtime: runtime, paths: paths)
        // 64-bit DLLs go to system32, 32-bit to syswow64 (Windows' naming, not a typo).
        let archs: [(String, URL)] = [("x86_64", bottle.system32), ("i386", bottle.syswow64)]
        return archs.flatMap { arch, dest in
            backend.providedDLLs.map { dll in
                CopyStep(
                    source: src.appendingPathComponent("\(arch)/\(dll).dll"),
                    destination: dest.appendingPathComponent("\(dll).dll")
                )
            }
        }
    }

    /// Executes the plan, skipping DLLs the backend doesn't ship for an arch.
    public func install(backend: any GraphicsBackend, runtime: WineRuntime, bottle: Bottle) throws {
        let fm = FileManager.default
        for step in plan(backend: backend, runtime: runtime, bottle: bottle) {
            guard fm.fileExists(atPath: step.source.path) else { continue }
            try fm.createDirectory(at: step.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: step.destination.path) {
                try fm.removeItem(at: step.destination)
            }
            try fm.copyItem(at: step.source, to: step.destination)
        }
        TetherLog.launch.info("Installed backend \(backend.id.rawValue, privacy: .public) into \(bottle.name, privacy: .public)")
    }
}
