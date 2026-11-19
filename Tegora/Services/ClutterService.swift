import CryptoKit
import Foundation
import UniformTypeIdentifiers
import Vision

struct CatalogEntry: Hashable {
    let url: URL
    let size: Int64
    let modified: Date?
    let accessed: Date?

    var lastUsed: Date? {
        [modified, accessed].compactMap { $0 }.max()
    }
    var item: FoundItem { FoundItem(url: url, size: size, modified: lastUsed) }
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let items: [FoundItem]
    var fileSize: Int64 { items.first?.size ?? 0 }
    var wastedBytes: Int64 { fileSize * Int64(max(items.count - 1, 0)) }
}

struct KindBreakdown: Identifiable {
    let kind: String
    let symbol: String
    let size: Int64
    let count: Int
    var id: String { kind }
}

enum ClutterService {

    static var defaultRoots: [URL] {
        ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
            .map { FileUtilities.home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Catalog

    /// Walks the chosen folders once and records every regular file. App bundles and other packages are skipped
    /// so their contents are never offered as individual files.
    static func catalog(roots: [URL], progress: (Int) -> Void) -> [CatalogEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey,
                                      .contentModificationDateKey, .contentAccessDateKey]
        var entries: [CatalogEntry] = []
        for root in roots {
            guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                          errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in en {
                if Task.isCancelled { return entries }
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
                let size = Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
                entries.append(CatalogEntry(url: url, size: size,
                                            modified: v.contentModificationDate, accessed: v.contentAccessDate))
                if entries.count % 500 == 0 { progress(entries.count) }
            }
        }
        progress(entries.count)
        return entries
    }

    static func largeFiles(_ catalog: [CatalogEntry], minimum: Int64 = 100 * 1_048_576) -> [FoundItem] {
        catalog.filter { $0.size >= minimum }.sorted { $0.size > $1.size }.map(\.item)
    }

    static func oldFiles(_ catalog: [CatalogEntry], olderThanDays days: Int = 365, minimum: Int64 = 1_048_576) -> [FoundItem] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return catalog.filter { entry in
            guard let used = entry.lastUsed else { return false }
            return used < cutoff && entry.size >= minimum
        }.sorted { $0.size > $1.size }.map(\.item)
    }

    static func downloads() -> [FoundItem] {
        let dir = FileUtilities.home.appendingPathComponent("Downloads")
        return FileUtilities.children(of: dir)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { FoundItem(url: $0, size: FileUtilities.size(of: $0), modified: FileUtilities.modificationDate($0)) }
            .sorted { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
    }

    static func breakdown(_ catalog: [CatalogEntry]) -> [KindBreakdown] {
        var sizes: [String: (Int64, Int)] = [:]
        for e in catalog {
            let k = kind(of: e.url)
            let cur = sizes[k] ?? (0, 0)
            sizes[k] = (cur.0 + e.size, cur.1 + 1)
        }
        return sizes.map { KindBreakdown(kind: $0.key, symbol: symbol(for: $0.key), size: $0.value.0, count: $0.value.1) }
            .sorted { $0.size > $1.size }
    }

    private static func kind(of url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return "Other" }
        if type.conforms(to: .image) { return "Images" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "Videos" }
        if type.conforms(to: .audio) { return "Audio" }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return "Archives" }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .content) { return "Documents" }
        return "Other"
    }

    private static func symbol(for kind: String) -> String {
        switch kind {
        case "Images": return "photo"
        case "Videos": return "film"
        case "Audio": return "music.note"
        case "Archives": return "archivebox"
        case "Documents": return "doc"
        default: return "questionmark.folder"
        }
    }

    // MARK: Duplicates

    /// Files are compared by size, then by a hash of their first 64 KB, then by a hash of the full contents,
    /// so two files are only reported as duplicates when every byte matches (SHA-256).
    static func findDuplicates(_ catalog: [CatalogEntry], minimum: Int64 = 100 * 1024,
                               progress: (String, Double) -> Void) -> [DuplicateGroup] {
        let candidates = Dictionary(grouping: catalog.filter { $0.size >= minimum }, by: \.size)
            .values.filter { $0.count > 1 }
        let total = max(candidates.reduce(0) { $0 + $1.count }, 1)
        var done = 0
        var groups: [DuplicateGroup] = []

        for sameSize in candidates {
            if Task.isCancelled { break }
            var byPartial: [String: [CatalogEntry]] = [:]
            for e in sameSize {
                if let h = hash(e.url, limit: 64 * 1024) { byPartial[h, default: []].append(e) }
                done += 1
                progress("Comparing files…", Double(done) / Double(total))
            }
            for partial in byPartial.values where partial.count > 1 {
                var byFull: [String: [CatalogEntry]] = [:]
                for e in partial {
                    if let h = hash(e.url, limit: nil) { byFull[h, default: []].append(e) }
                }
                for same in byFull.values where same.count > 1 {
                    groups.append(DuplicateGroup(items: same.map(\.item).sorted { $0.url.path < $1.url.path }))
                }
            }
        }
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    private static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            let chunk = min(remaining, 1 << 20)
            guard let data = try? handle.read(upToCount: chunk), !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Similar images

    /// Groups visually similar photos using Apple's Vision feature prints. Capped to keep scans responsive.
    static func findSimilarImages(_ catalog: [CatalogEntry], threshold: Float = 0.3, cap: Int = 1500,
                                  progress: (String, Double) -> Void) -> [DuplicateGroup] {
        let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "gif", "bmp"]
        let images = catalog.filter { exts.contains($0.url.pathExtension.lowercased()) && $0.size > 20 * 1024 }
            .sorted { $0.size > $1.size }.prefix(cap)

        var prints: [(CatalogEntry, VNFeaturePrintObservation)] = []
        var index = 0
        for entry in images {
            if Task.isCancelled { break }
            index += 1
            progress("Analysing images…", Double(index) / Double(max(images.count, 1)) * 0.8)
            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(url: entry.url, options: [:])
            if (try? handler.perform([request])) != nil, let obs = request.results?.first {
                prints.append((entry, obs))
            }
        }

        var assigned = Set<URL>()
        var groups: [DuplicateGroup] = []
        for (i, base) in prints.enumerated() {
            if Task.isCancelled { break }
            if i % 20 == 0 { progress("Comparing images…", 0.8 + 0.2 * Double(i) / Double(max(prints.count, 1))) }
            if assigned.contains(base.0.url) { continue }
            var members = [base.0]
            for other in prints[(i + 1)...] where !assigned.contains(other.0.url) {
                var distance: Float = 0
                if (try? base.1.computeDistance(&distance, to: other.1)) != nil, distance < threshold {
                    members.append(other.0)
                }
            }
            if members.count > 1 {
                members.forEach { assigned.insert($0.url) }
                groups.append(DuplicateGroup(items: members.map(\.item)))
            }
        }
        return groups.sorted { $0.items.count > $1.items.count }
    }

    // MARK: Removal

    /// Moves the selected files to the Trash so everything stays recoverable.
    static func remove(_ items: [FoundItem]) -> OperationReport {
        var report = OperationReport()
        for item in items {
            if let error = FileUtilities.moveToTrash(item.url) {
                report.errors.append(error)
            } else {
                report.removedCount += 1
                report.freedBytes += item.size
            }
        }
        return report
    }
}
