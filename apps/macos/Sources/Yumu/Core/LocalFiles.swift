import Darwin
import Foundation

/// A world inside an instance's `saves/`. Read from disk until the core lists saves itself.
struct WorldInfo: Identifiable, Hashable, Sendable {
    let name: String
    let path: URL
    let sizeBytes: UInt64
    let modifiedAt: Date

    var id: String { path.path }
}

/// Resource usage of one game process, sampled by the launcher.
struct ProcessStats: Hashable, Sendable {
    let residentBytes: UInt64
    let cpuPercent: Double
}

/// Everything the launcher reads straight from the data directory.
enum LocalFiles {
    static let dataDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Yumu")
    }()

    static func instanceDirectory(_ id: String) -> URL { dataDirectory.appending(path: "instances/\(id)") }
    static func gameDirectory(_ id: String) -> URL { instanceDirectory(id).appending(path: ".minecraft") }
    static func logsDirectory(_ id: String) -> URL { instanceDirectory(id).appending(path: "logs") }

    static func worlds(_ id: String) -> [WorldInfo] {
        let saves = gameDirectory(id).appending(path: "saves")
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: saves, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]) else { return [] }
        return entries.compactMap { url -> WorldInfo? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return WorldInfo(name: url.lastPathComponent, path: url, sizeBytes: directorySize(url), modifiedAt: modified)
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    static func logFiles(_ id: String) -> [URL] {
        let dir = logsDirectory(id)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// The last `lines` lines of a log; reads at most the final 512 KB so huge logs stay cheap.
    static func tail(_ url: URL, lines: Int = 400) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 512 * 1024
        try? handle.seek(toOffset: size > window ? size - window : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }

    private static func directorySize(_ url: URL) -> UInt64 {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in walker {
            total += UInt64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

/// Samples CPU and memory of game processes through libproc; no core round-trip needed.
struct ProcessSampler {
    private var lastCpu: [Int32: (time: UInt64, at: Date)] = [:]

    mutating func sample(_ pid: Int32) -> ProcessStats? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard status == 0 else { return nil }
        let now = Date()
        let cpuTime = info.ri_user_time + info.ri_system_time
        var percent = 0.0
        if let last = lastCpu[pid] {
            let elapsed = now.timeIntervalSince(last.at)
            if elapsed > 0 { percent = Double(cpuTime - last.time) / Self.nanosecondsPerSecond / elapsed * 100 }
        }
        lastCpu[pid] = (cpuTime, now)
        return ProcessStats(residentBytes: info.ri_resident_size, cpuPercent: percent)
    }

    mutating func forget(_ pid: Int32) { lastCpu[pid] = nil }

    /// `ri_*_time` is in Mach absolute time units; convert through the timebase.
    private static let nanosecondsPerSecond: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer)
    }()
}
