import Foundation

enum FileUtilities {
    static let fm = FileManager.default
    static var home: URL { fm.homeDirectoryForCurrentUser }
    static var library: URL { home.appendingPathComponent("Library") }

    private static let sizeKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey
    ]

    /// Allocated size of a single file on disk.
    static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: Set(sizeKeys))
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
    }

    /// Total allocated size of a file or directory tree. Does not follow symlinks.
    /// Checks for cancellation so long scans can be stopped.
    static func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true { return 0 }
        if values?.isDirectory != true { return fileSize(url) }

        var total: Int64 = 0
        guard let en = fm.enumerator(at: url,
                                     includingPropertiesForKeys: sizeKeys,
                                     options: [],
                                     errorHandler: { _, _ in true }) else { return 0 }
        for case let child as URL in en {
            if Task.isCancelled { return total }
            let v = try? child.resourceValues(forKeys: Set(sizeKeys))
            if v?.isSymbolicLink == true { continue }
            if v?.isRegularFile == true {
                total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0)
            }
        }
        return total
    }

    /// Immediate children of a directory (hidden files included). Empty if unreadable.
    static func children(of url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func accessDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
    }

    /// Paths that must never be touched, regardless of what a scan finds.
    static func isProtected(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        let blocked = ["/System", "/usr", "/bin", "/sbin", "/private/var/db", "/Library/Apple", "/cores"]
        if blocked.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { return true }
        if p == "/" || p == home.path || p == library.path { return true }
        // Top-level folders that must never be removed as a whole.
        let topLevel = ["/Applications", "/Library", "/Users", "/private", "/opt", "/Volumes", "/var", "/etc", "/tmp"]
        if topLevel.contains(p) { return true }
        let homeFolders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications"]
        if homeFolders.contains(where: { home.appendingPathComponent($0).path == p }) { return true }
        if p.hasPrefix("/Applications/") {
            // Apple's own apps live here and are sealed by the system.
            let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
            if bundleID.hasPrefix("com.apple.") { return true }
        }
        return false
    }

    /// Moves a file to the Trash (recoverable). Returns an error message on failure.
    @discardableResult
    static func moveToTrash(_ url: URL) -> String? {
        if isProtected(url) { return "\(url.lastPathComponent) is protected by macOS and was skipped." }
        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
            return nil
        } catch {
            return "Couldn't remove \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Permanently deletes a file. Used only for emptying the Trash and other already-discarded data.
    @discardableResult
    static func permanentlyDelete(_ url: URL) -> String? {
        if isProtected(url) { return "\(url.lastPathComponent) is protected by macOS and was skipped." }
        do {
            try fm.removeItem(at: url)
            return nil
        } catch {
            return "Couldn't delete \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Whether the app can read a location that requires Full Disk Access.
    static func hasFullDiskAccess() -> Bool {
        let probe = library.appendingPathComponent("Safari")
        guard fm.fileExists(atPath: probe.path) else {
            // Fall back to another protected location that always exists.
            return (try? fm.contentsOfDirectory(atPath: library.appendingPathComponent("Mail").path)) != nil
        }
        return (try? fm.contentsOfDirectory(atPath: probe.path)) != nil
    }
}
