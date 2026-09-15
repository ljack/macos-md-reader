import Foundation

/// kqueue-based watcher. Survives atomic saves (write-to-temp + rename) by re-opening the path.
final class FileWatcher {
    private let url: URL
    private let handler: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var reopenAttempts = 0

    init(url: URL, handler: @escaping () -> Void) {
        self.url = url
        self.handler = handler
        start()
    }

    deinit { stop() }

    private func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { retryLater(); return }
        let reattached = reopenAttempts > 0
        reopenAttempts = 0
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke, .attrib],
            queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let events = src.data
            if !events.isDisjoint(with: [.delete, .rename, .revoke]) {
                self.stop()
                self.retryLater()
            }
            self.scheduleFire()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        // An atomic save can leave the path absent while the earlier reload ran; the new file
        // is only known to exist now, so read it.
        if reattached { scheduleFire() }
    }

    private func stop() {
        source?.cancel()
        source = nil
    }

    private func retryLater() {
        reopenAttempts += 1
        guard reopenAttempts < 40 else { return } // ~10 s, then give up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.source == nil else { return }
            self.start()
        }
    }

    private func scheduleFire() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.handler() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
}
