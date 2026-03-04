import Foundation

final class ModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var downloadedModels: Set<String> = []
    /// Per-model download state
    @Published var activeDownloads: [String: DownloadState] = [:]

    struct DownloadState {
        var progress: Double = 0
        var error: String?
    }

    private var tasks: [URLSessionDownloadTask: LocalModelSize] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.isDiscretionary = false // not background-only
        config.sessionSendsLaunchEvents = false
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    override init() {
        super.init()
        refreshDownloadedModels()
    }

    func refreshDownloadedModels() {
        var models = Set<String>()
        for size in LocalModelSize.allCases {
            if findModelPath(for: size) != nil {
                models.insert(size.rawValue)
            }
        }
        downloadedModels = models
    }

    /// Finds the actual path for a model file, checking local storage first, then system paths.
    func findModelPath(for size: LocalModelSize) -> URL? {
        // 1. Check App Storage (Sandboxed/Internal)
        let localPath = Storage.modelsDirectory.appendingPathComponent(size.fileName)
        if FileManager.default.fileExists(atPath: localPath.path) {
            return localPath
        }

        // 2. Check Legacy / System paths
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let systemPaths = [
            "/opt/homebrew/share/whisper-cpp/models/\(size.fileName)",
            "/usr/local/share/whisper-cpp/models/\(size.fileName)",
            homeDir.appendingPathComponent("Library/Application Support/superwhisper/Models/\(size.fileName)").path,
            homeDir.appendingPathComponent(".cache/whisper/\(size.fileName)").path
        ]

        for path in systemPaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    func isModelDownloaded(_ size: LocalModelSize) -> Bool {
        downloadedModels.contains(size.rawValue)
    }

    func isDownloading(_ size: LocalModelSize) -> Bool {
        activeDownloads[size.rawValue] != nil
    }

    func progress(for size: LocalModelSize) -> Double {
        activeDownloads[size.rawValue]?.progress ?? 0
    }

    func error(for size: LocalModelSize) -> String? {
        activeDownloads[size.rawValue]?.error
    }

    var isAnyDownloading: Bool {
        !activeDownloads.isEmpty
    }

    func downloadModel(_ size: LocalModelSize) {
        guard activeDownloads[size.rawValue] == nil else { return }

        activeDownloads[size.rawValue] = DownloadState()

        let task = session.downloadTask(with: size.downloadURL)
        tasks[task] = size
        task.resume()
    }

    func cancelDownload(_ size: LocalModelSize) {
        for (task, model) in tasks where model == size {
            task.cancel()
            tasks.removeValue(forKey: task)
        }
        activeDownloads.removeValue(forKey: size.rawValue)
    }

    func deleteModel(_ size: LocalModelSize) {
        let path = Storage.modelsDirectory.appendingPathComponent(size.fileName)
        try? FileManager.default.removeItem(at: path)
        refreshDownloadedModels()
    }

    func modelFileSize(_ size: LocalModelSize) -> String? {
        let path = Storage.modelsDirectory.appendingPathComponent(size.fileName)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let fileSize = attrs[.size] as? UInt64
        else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let size = tasks[downloadTask] else { return }
        if totalBytesExpectedToWrite > 0 {
            activeDownloads[size.rawValue]?.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let size = tasks[downloadTask] else { return }
        let destination = Storage.modelsDirectory.appendingPathComponent(size.fileName)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            refreshDownloadedModels()
        } catch {
            activeDownloads[size.rawValue]?.error = error.localizedDescription
        }

        tasks.removeValue(forKey: downloadTask)
        activeDownloads.removeValue(forKey: size.rawValue)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let dlTask = task as? URLSessionDownloadTask,
              let size = tasks[dlTask] else { return }
        if let error = error as? NSError, error.code != NSURLErrorCancelled {
            activeDownloads[size.rawValue]?.error = error.localizedDescription
        }
        tasks.removeValue(forKey: dlTask)
        // Keep activeDownloads entry for error display, remove after delay
        if activeDownloads[size.rawValue]?.error != nil {
            let key = size.rawValue
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.activeDownloads.removeValue(forKey: key)
            }
        } else {
            activeDownloads.removeValue(forKey: size.rawValue)
        }
    }
}
