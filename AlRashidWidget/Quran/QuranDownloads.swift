//
//  QuranDownloads.swift
//  AlRashid Prayer Widget
//
//  Quran player (v2.1.0-private): offline downloads of whole surahs.
//  Files live at Application Support/QuranAudio/{reciterId}/{n}.mp3;
//  the player prefers a downloaded file over the stream. Target
//  Membership: AlRashidWidget only.
//

import Foundation

final class QuranDownloads: NSObject, ObservableObject {
    /// In-flight progress (0...1) per key, only while downloading.
    @Published private(set) var progressByKey: [String: Double] = [:]
    /// Keys whose file is fully on disk. Refreshed from the folder.
    @Published private(set) var downloadedKeys: Set<String> = []

    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()
    private var tasksById: [Int: String] = [:]
    private var tasksByKey: [String: URLSessionDownloadTask] = [:]
    private let bookkeepingLock = NSLock()

    override init() {
        super.init()
        refreshDownloaded()
    }

    // MARK: Keys & files

    static func key(reciterId: String, surahNumber: Int) -> String {
        "\(reciterId)/\(surahNumber)"
    }

    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("QuranAudio", isDirectory: true)
    }

    static func fileURL(reciterId: String, surahNumber: Int) -> URL {
        rootDirectory
            .appendingPathComponent(reciterId, isDirectory: true)
            .appendingPathComponent("\(surahNumber).mp3")
    }

    /// The on-disk file for a (reciter, surah), when fully downloaded.
    static func localFileURL(reciterId: String, surahNumber: Int) -> URL? {
        let url = fileURL(reciterId: reciterId, surahNumber: surahNumber)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: State

    func isDownloaded(reciterId: String, surahNumber: Int) -> Bool {
        downloadedKeys.contains(Self.key(reciterId: reciterId, surahNumber: surahNumber))
    }

    func isDownloading(reciterId: String, surahNumber: Int) -> Bool {
        progressByKey[Self.key(reciterId: reciterId, surahNumber: surahNumber)] != nil
    }

    func progress(reciterId: String, surahNumber: Int) -> Double? {
        progressByKey[Self.key(reciterId: reciterId, surahNumber: surahNumber)]
    }

    var downloadedCount: Int { downloadedKeys.count }

    /// Total bytes of downloaded audio on disk.
    var totalBytes: Int64 {
        var total: Int64 = 0
        for key in downloadedKeys {
            let parts = key.split(separator: "/")
            guard parts.count == 2, let number = Int(parts[1]) else { continue }
            let url = Self.fileURL(reciterId: String(parts[0]), surahNumber: number)
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    func refreshDownloaded() {
        var found: Set<String> = []
        let fm = FileManager.default
        if let reciters = try? fm.contentsOfDirectory(atPath: Self.rootDirectory.path) {
            for reciterId in reciters {
                let dir = Self.rootDirectory.appendingPathComponent(reciterId, isDirectory: true)
                guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
                for file in files where file.hasSuffix(".mp3") {
                    let number = file.dropLast(4)
                    if Int(number) != nil {
                        found.insert(Self.key(reciterId: reciterId, surahNumber: Int(number)!))
                    }
                }
            }
        }
        downloadedKeys = found
    }

    // MARK: Download / cancel / delete

    func download(surahNumber: Int, reciterId: String) {
        let key = Self.key(reciterId: reciterId, surahNumber: surahNumber)
        guard !downloadedKeys.contains(key), progressByKey[key] == nil else { return }
        guard let url = QuranLibrary.streamURL(surahNumber: surahNumber, reciterId: reciterId)
        else { return }
        let task = session.downloadTask(with: url)
        bookkeepingLock.lock()
        tasksById[task.taskIdentifier] = key
        tasksByKey[key] = task
        bookkeepingLock.unlock()
        progressByKey[key] = 0
        task.resume()
    }

    func cancel(surahNumber: Int, reciterId: String) {
        let key = Self.key(reciterId: reciterId, surahNumber: surahNumber)
        bookkeepingLock.lock()
        let task = tasksByKey[key]
        bookkeepingLock.unlock()
        task?.cancel()
        // didCompleteWithError tidies the bookkeeping.
    }

    func delete(surahNumber: Int, reciterId: String) {
        cancel(surahNumber: surahNumber, reciterId: reciterId)
        let url = Self.fileURL(reciterId: reciterId, surahNumber: surahNumber)
        try? FileManager.default.removeItem(at: url)
        downloadedKeys.remove(Self.key(reciterId: reciterId, surahNumber: surahNumber))
    }

    // MARK: Delegate bookkeeping (called off the main queue)

    private func key(for task: URLSessionTask) -> String? {
        bookkeepingLock.lock()
        defer { bookkeepingLock.unlock() }
        return tasksById[task.taskIdentifier]
    }

    private func finish(task: URLSessionTask) -> String? {
        bookkeepingLock.lock()
        let key = tasksById.removeValue(forKey: task.taskIdentifier)
        if let key { tasksByKey.removeValue(forKey: key) }
        bookkeepingLock.unlock()
        return key
    }

    private func publishProgress(_ value: Double, forKey key: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let old = self.progressByKey[key], value - old < 0.01, value < 1 { return }
            self.progressByKey[key] = value
        }
    }

    private func clearProgress(forKey key: String) {
        DispatchQueue.main.async { [weak self] in
            self?.progressByKey.removeValue(forKey: key)
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension QuranDownloads: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let key = key(for: downloadTask), totalBytesExpectedToWrite > 0 else { return }
        publishProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite),
                        forKey: key)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this returns: move it now.
        guard let key = key(for: downloadTask) else { return }
        let parts = key.split(separator: "/")
        guard parts.count == 2, let number = Int(parts[1]) else { return }
        let destination = Self.fileURL(reciterId: String(parts[0]), surahNumber: number)
        let fm = FileManager.default
        try? fm.createDirectory(at: destination.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try? fm.removeItem(at: destination)
        try? fm.moveItem(at: location, to: destination)
        DispatchQueue.main.async { [weak self] in
            self?.downloadedKeys.insert(key)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let key = finish(task: task) else { return }
        clearProgress(forKey: key)
    }
}
