import Foundation

final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let path: String
    private let callback: () -> Void

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.callback = onChange
        start()
    }

    deinit { stop() }

    private func start() {
        // Watch the directory (not the file itself) to detect atomic rename-based writes
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent().path

        // Ensure directory exists so we can open a file descriptor
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source?.setEventHandler { [weak self] in self?.callback() }
        source?.setCancelHandler { close(fd) }
        source?.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
