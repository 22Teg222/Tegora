import Foundation

/// A file or folder discovered by a scan. Identity is the file URL.
struct FoundItem: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date?
    var note: String? = nil

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct OperationReport {
    var removedCount = 0
    var freedBytes: Int64 = 0
    var errors: [String] = []

    mutating func merge(_ other: OperationReport) {
        removedCount += other.removedCount
        freedBytes += other.freedBytes
        errors += other.errors
    }
}

enum ScanPhase: Equatable {
    case idle
    case running(String)
    case finished
}
