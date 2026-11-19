import Foundation

/// Finds junk in well-known locations and removes only what the user has selected.
enum CleanupService {
    private static let fm = FileManager.default
    private static var lib: URL { FileUtilities.library }

    // MARK: Scanning

    /// Scans one category. Blocking; call from a background task.
    static func scan(_ category: CleanupCategory) -> CategoryResult {
        var warning: String?
        if category.needsFullDiskAccess && !FileUtilities.hasFullDiskAccess() {
            warning = "Full Disk Access is off, so Tegora may not see everything here."
        }

        let roots: [URL]
        switch category {
        case .systemCache:
            return result(category, from: FileUtilities.children(of: lib.appendingPathComponent("Caches"))
                .filter { !$0.lastPathComponent.hasPrefix("com.apple.") }, warning: warning)
        case .logs:
            roots = [lib.appendingPathComponent("Logs")]
        case .temporary:
            return result(category, from: temporaryItems(), warning: warning)
        case .languages:
            return CategoryResult(category: category, items: languageItems(), warning: warning)
        case .xcode:
            let dev = lib.appendingPathComponent("Developer")
            roots = [dev.appendingPathComponent("Xcode/DerivedData"),
                     dev.appendingPathComponent("Xcode/iOS DeviceSupport"),
                     dev.appendingPathComponent("Xcode/watchOS DeviceSupport"),
                     dev.appendingPathComponent("CoreSimulator/Caches")]
        case .mail:
            roots = [lib.appendingPathComponent("Containers/com.apple.mail/Data/Library/Mail Downloads")]
            warning = warning ?? "Only copies of attachments you opened from Mail are listed. Attachments stored inside your mailboxes are never touched."
        case .iosBackups:
            roots = [lib.appendingPathComponent("Application Support/MobileSync/Backup")]
        case .trash:
            roots = [FileUtilities.home.appendingPathComponent(".Trash")]
        case .brokenPreferences:
            return CategoryResult(category: category, items: brokenPreferences(), warning: warning)
        }
        return result(category, from: roots.flatMap { FileUtilities.children(of: $0) }, warning: warning)
    }

    private static func result(_ category: CleanupCategory, from urls: [URL], warning: String?) -> CategoryResult {
        var items: [FoundItem] = []
        for url in urls {
            if Task.isCancelled { break }
            if url.lastPathComponent == ".DS_Store" || url.lastPathComponent == ".localized" { continue }
            let size = FileUtilities.size(of: url)
            items.append(FoundItem(url: url, size: size, modified: FileUtilities.modificationDate(url)))
        }
        items.sort { $0.size > $1.size }
        return CategoryResult(category: category, items: items, warning: warning)
    }

    private static func temporaryItems() -> [URL] {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let cutoff = Date().addingTimeInterval(-86_400)
        return FileUtilities.children(of: tmp).filter { url in
            guard let modified = FileUtilities.modificationDate(url) else { return false }
            return modified < cutoff
        }
    }

    private static func brokenPreferences() -> [FoundItem] {
        let prefs = lib.appendingPathComponent("Preferences")
        var items: [FoundItem] = []
        for url in FileUtilities.children(of: prefs) where url.pathExtension == "plist" {
            if url.lastPathComponent.hasPrefix("com.apple.") || url.lastPathComponent.hasPrefix(".") { continue }
            let size = FileUtilities.fileSize(url)
            var reason: String?
            if let data = try? Data(contentsOf: url) {
                if data.isEmpty {
                    reason = "File is empty"
                } else if (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) == nil {
                    reason = "File can't be read as a property list"
                }
            } else {
                continue // unreadable for permission reasons: not proof it is broken
            }
            if let reason {
                items.append(FoundItem(url: url, size: size, modified: FileUtilities.modificationDate(url), note: reason))
            }
        }
        return items.sorted { $0.name < $1.name }
    }

    private static func languageItems() -> [FoundItem] {
        var keep: Set<String> = ["en", "base"]
        for id in Locale.preferredLanguages {
            if let code = languageCode(id) { keep.insert(code) }
        }
        var items: [FoundItem] = []
        let appDirs = [URL(fileURLWithPath: "/Applications"), FileUtilities.home.appendingPathComponent("Applications")]
        for dir in appDirs {
            for app in FileUtilities.children(of: dir) where app.pathExtension == "app" {
                if Task.isCancelled { return items }
                let bundle = Bundle(url: app)
                if (bundle?.bundleIdentifier ?? "").hasPrefix("com.apple.") { continue }
                // Mac App Store apps are signed and sealed; changing them would invalidate the app.
                if fm.fileExists(atPath: app.appendingPathComponent("Contents/_MASReceipt").path) { continue }
                let resources = app.appendingPathComponent("Contents/Resources")
                for entry in FileUtilities.children(of: resources) where entry.pathExtension == "lproj" {
                    let base = entry.deletingPathExtension().lastPathComponent
                    guard let code = languageCode(base), code.count <= 3, !keep.contains(code) else { continue }
                    let size = FileUtilities.size(of: entry)
                    items.append(FoundItem(url: entry, size: size, modified: nil,
                                           note: app.deletingPathExtension().lastPathComponent))
                }
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    private static func languageCode(_ identifier: String) -> String? {
        let first = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        return first?.lowercased()
    }

    // MARK: Removal

    /// Removes the given items. Anything outside the folders Tegora scans, or protected by macOS, is refused.
    static func remove(_ items: [FoundItem], category: CleanupCategory) -> OperationReport {
        var report = OperationReport()
        for item in items {
            guard isAllowedLocation(item.url) else {
                report.errors.append("\(item.name) is outside the folders Tegora cleans and was skipped.")
                continue
            }
            let error = category.deletesPermanently
                ? FileUtilities.permanentlyDelete(item.url)
                : FileUtilities.moveToTrash(item.url)
            if let error {
                report.errors.append(error)
            } else {
                report.removedCount += 1
                report.freedBytes += item.size
            }
        }
        return report
    }

    private static func isAllowedLocation(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let allowed = [FileUtilities.home.path, "/Applications", NSTemporaryDirectory(), "/private/var/folders"]
        return allowed.contains { path.hasPrefix($0) } && !FileUtilities.isProtected(url)
    }
}
