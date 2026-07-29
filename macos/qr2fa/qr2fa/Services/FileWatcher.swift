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

        // Ensure directory exists so we can open a file descriptor.
        // 저장 디렉터리를 실제로 처음 만드는 건 대개 save()가 아니라 여기다(StorageService.init이
        // 곧바로 감시를 시작한다). 그래서 여기서도 0700으로 만들어야 한다 — 0755로 만들어지면
        // save()의 createDirectory는 이미 존재하는 디렉터리라 권한을 고치지 않는다.
        try? StorageService.createDirectory(dir)

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
