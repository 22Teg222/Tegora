import Foundation

struct SpaceNode: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let isDirectory: Bool
    var id: URL { url }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
}

enum SpaceLensService {

    /// Sizes every item directly inside `folder`, largest first. Folder sizes include everything beneath them.
    /// Items are measured in parallel; `progress` reports how many are done.
    static func scan(folder: URL, progress: @escaping @Sendable (Int, Int) -> Void) async -> [SpaceNode] {
        let children = FileUtilities.children(of: folder).filter { !FileUtilities.isProtectedForScan($0) }
        let total = children.count
        var nodes: [SpaceNode] = []
        var finished = 0

        await withTaskGroup(of: SpaceNode.self) { group in
            var iterator = children.makeIterator()
            var running = 0
            let maxConcurrent = 6

            func addNext(_ group: inout TaskGroup<SpaceNode>) -> Bool {
                guard let url = iterator.next() else { return false }
                group.addTask {
                    let isDir = FileUtilities.isDirectory(url)
                    return SpaceNode(url: url, size: FileUtilities.size(of: url), isDirectory: isDir)
                }
                return true
            }

            while running < maxConcurrent, addNext(&group) { running += 1 }
            while let node = await group.next() {
                nodes.append(node)
                finished += 1
                progress(finished, total)
                if addNext(&group) {} // keep the pool full
            }
        }
        return nodes.filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    /// The biggest individual files under a folder.
    static func largestFiles(in folder: URL, limit: Int = 25) -> [FoundItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let en = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                      options: [.skipsPackageDescendants],
                                                      errorHandler: { _, _ in true }) else { return [] }
        var top: [FoundItem] = []
        for case let url as URL in en {
            if Task.isCancelled { break }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let size = v.totalFileAllocatedSize else { continue }
            let item = FoundItem(url: url, size: Int64(size), modified: v.contentModificationDate)
            if top.count < limit {
                top.append(item)
                top.sort { $0.size > $1.size }
            } else if let last = top.last, item.size > last.size {
                top[top.count - 1] = item
                top.sort { $0.size > $1.size }
            }
        }
        return top
    }
}

extension FileUtilities {
    /// Locations that aren't worth (or safe) walking when visualising storage.
    static func isProtectedForScan(_ url: URL) -> Bool {
        let p = url.path
        return p == "/dev" || p == "/Volumes" || p == "/System/Volumes" || p.hasPrefix("/private/var/vm")
    }
}
