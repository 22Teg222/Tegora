import Foundation

struct DiskInfo {
    let total: Int64
    let available: Int64
    var used: Int64 { max(total - available, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

enum StorageService {
    /// Real capacity of the startup volume. "Available" includes space macOS can reclaim on demand,
    /// which matches what Finder reports.
    static func startupDisk() -> DiskInfo? {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? url.resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity,
              let available = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskInfo(total: Int64(total), available: available)
    }
}
