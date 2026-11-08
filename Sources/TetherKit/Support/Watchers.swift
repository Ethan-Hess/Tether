import Foundation

/// Coalescing wake-up: any number of `signal()` calls before the next `next()` count as one.
/// The consumer is a single task.
public final class WakeSignal: @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var iterator: AsyncStream<Void>.AsyncIterator

    public init() {
        var cont: AsyncStream<Void>.Continuation!
        stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        continuation = cont
        iterator = stream.makeAsyncIterator()
    }

    public func signal() { continuation.yield() }

    /// Waits for a signal, or for `timeout` seconds if given. Returns at once if one is pending.
    public func next(timeout: TimeInterval? = nil) async {
        let timer = timeout.map { seconds in
            Task { [continuation] in
                try? await Task.sleep(for: .seconds(max(0, seconds)))
                continuation.yield()
            }
        }
        _ = await iterator.next()
        timer?.cancel()
    }

    public func finish() { continuation.finish() }
}

/// Calls `onChange` when a file is written to, without polling. If the file is replaced or doesn't
/// exist yet, it keeps trying to attach (once a second) until cancelled.
public final class FileChangeWatcher: @unchecked Sendable {
    private let path: String
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "dev.tether.filewatch", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var cancelled = false

    public init(url: URL, onChange: @escaping @Sendable () -> Void) {
        path = url.path
        self.onChange = onChange
        queue.async { self.attach() }
    }

    /// Whether the file is currently being watched. Without it, a caller should check on a timer.
    public var isWatching: Bool { queue.sync { source != nil } }

    public func cancel() {
        queue.sync {
            cancelled = true
            source?.cancel()
            source = nil
        }
    }

    private func attach() {
        guard !cancelled, source == nil else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            queue.asyncAfter(deadline: .now() + 1) { self.attach() }
            return
        }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .revoke], queue: queue)
        s.setEventHandler { [weak self] in
            guard let self, let s = self.source else { return }
            let events = s.data
            self.onChange()
            if !events.isDisjoint(with: [.delete, .rename, .revoke]) {
                s.cancel()
                self.source = nil
                self.queue.asyncAfter(deadline: .now() + 0.5) { self.attach() }
            }
        }
        s.setCancelHandler { close(fd) }
        source = s
        s.resume()
        onChange() // the file may have changed between the caller's last read and now
    }
}

/// Calls `onExit` when a process ends, without polling. Works for any process the user owns.
public final class ProcessExitWatcher: @unchecked Sendable {
    private let source: DispatchSourceProcess

    public init(pid: Int32, onExit: @escaping @Sendable () -> Void) {
        source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: DispatchQueue(label: "dev.tether.procwatch", qos: .utility))
        source.setEventHandler(handler: onExit)
        source.resume()
    }

    public func cancel() { source.cancel() }

    /// Whether a process with this ID exists (a signal-0 check; no process is touched).
    public static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
