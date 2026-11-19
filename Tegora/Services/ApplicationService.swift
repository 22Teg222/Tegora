import AppKit
import Foundation

enum ApplicationService {
    private static let fm = FileManager.default

    // MARK: Installed apps

    /// Lists apps in /Applications and ~/Applications. Sizes are computed here, so run off the main thread.
    static func installedApps() -> [InstalledApp] {
        let dirs = [URL(fileURLWithPath: "/Applications"), FileUtilities.home.appendingPathComponent("Applications")]
        var apps: [InstalledApp] = []
        for dir in dirs {
            for url in FileUtilities.children(of: dir) where url.pathExtension == "app" {
                if Task.isCancelled { return apps }
                let bundle = Bundle(url: url)
                let info = bundle?.infoDictionary ?? [:]
                let name = (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
                apps.append(InstalledApp(
                    url: url, name: name,
                    bundleID: bundle?.bundleIdentifier,
                    version: info["CFBundleShortVersionString"] as? String,
                    build: info["CFBundleVersion"] as? String,
                    size: FileUtilities.size(of: url),
                    isAppStore: fm.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt").path),
                    sparkleFeed: feed))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func isSystemApp(_ app: InstalledApp) -> Bool {
        (app.bundleID ?? "").hasPrefix("com.apple.")
    }

    static func isRunning(_ app: InstalledApp) -> Bool {
        guard let id = app.bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    // MARK: Leftovers

    /// Files an app typically leaves in the user's Library. Matching is by bundle identifier, which is specific
    /// enough to avoid catching unrelated files; the only name-based match is an exact folder in Application Support.
    static func leftovers(for app: InstalledApp) -> [FoundItem] {
        guard let id = app.bundleID?.lowercased(), !id.hasPrefix("com.apple.") else { return [] }
        let lib = FileUtilities.library
        let folders = ["Application Support", "Caches", "Preferences", "Containers", "Group Containers",
                       "Saved Application State", "Logs", "HTTPStorages", "WebKit", "Application Scripts",
                       "Cookies", "LaunchAgents"]
        var found: [URL] = []
        for folder in folders {
            for url in FileUtilities.children(of: lib.appendingPathComponent(folder)) {
                let n = url.lastPathComponent.lowercased()
                if n.contains(id) { found.append(url) }
            }
        }
        let support = lib.appendingPathComponent("Application Support").appendingPathComponent(app.name)
        if app.name.count >= 4, fm.fileExists(atPath: support.path), !found.contains(support) {
            found.append(support)
        }
        return found.map {
            FoundItem(url: $0, size: FileUtilities.size(of: $0), modified: FileUtilities.modificationDate($0))
        }.sorted { $0.size > $1.size }
    }

    /// Moves the app and the approved leftovers to the Trash.
    static func uninstall(_ app: InstalledApp, leftovers: [FoundItem]) -> OperationReport {
        var report = OperationReport()
        if isSystemApp(app) {
            report.errors.append("\(app.name) is part of macOS and can't be removed.")
            return report
        }
        if isRunning(app) {
            report.errors.append("\(app.name) is still running. Quit it and try again.")
            return report
        }
        if let error = FileUtilities.moveToTrash(app.url) {
            report.errors.append(error)
            return report // keep leftovers if the app itself couldn't be removed
        }
        report.removedCount += 1
        report.freedBytes += app.size
        for item in leftovers {
            let path = item.url.standardizedFileURL.path
            guard path.hasPrefix(FileUtilities.library.path + "/") else {
                report.errors.append("\(item.name) is outside your Library and was skipped.")
                continue
            }
            if let error = FileUtilities.moveToTrash(item.url) {
                report.errors.append(error)
            } else {
                report.removedCount += 1
                report.freedBytes += item.size
            }
        }
        return report
    }

    // MARK: Updates

    /// Checks for a newer version. Sparkle apps are checked against their own appcast, App Store apps
    /// against Apple's public lookup service. Returns nil when the app is current or can't be checked.
    static func checkForUpdate(_ app: InstalledApp) async -> AppUpdateInfo? {
        if let feed = app.sparkleFeed {
            return await sparkleUpdate(app, feed: feed)
        }
        if app.isAppStore, let id = app.bundleID {
            return await appStoreUpdate(app, bundleID: id)
        }
        return nil
    }

    static func canCheckForUpdates(_ app: InstalledApp) -> Bool {
        app.sparkleFeed != nil || (app.isAppStore && app.bundleID != nil)
    }

    private static func isNewer(_ latest: String, than current: String?) -> Bool {
        guard let current else { return false }
        return latest.compare(current, options: .numeric) == .orderedDescending
    }

    private static func appStoreUpdate(_ app: InstalledApp, bundleID: String) async -> AppUpdateInfo? {
        guard let encoded = bundleID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(encoded)&entity=macSoftware"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let latest = first["version"] as? String,
              isNewer(latest, than: app.version) else { return nil }
        let link = (first["trackViewUrl"] as? String).flatMap(URL.init(string:))
        return AppUpdateInfo(latestVersion: latest, downloadURL: link)
    }

    private static func sparkleUpdate(_ app: InstalledApp, feed: URL) async -> AppUpdateInfo? {
        guard let (data, _) = try? await URLSession.shared.data(from: feed) else { return nil }
        let parser = AppcastParser()
        let entries = parser.parse(data)
        // Prefer the marketing version; fall back to build numbers for apps that only publish those.
        let best = entries.max { a, b in
            (a.shortVersion ?? a.version ?? "").compare(b.shortVersion ?? b.version ?? "", options: .numeric) == .orderedAscending
        }
        guard let best else { return nil }
        if let short = best.shortVersion, isNewer(short, than: app.version) {
            return AppUpdateInfo(latestVersion: short, downloadURL: best.url)
        }
        if best.shortVersion == nil, let build = best.version, isNewer(build, than: app.build) {
            return AppUpdateInfo(latestVersion: build, downloadURL: best.url)
        }
        return nil
    }

    // MARK: Background items

    static func backgroundItems() -> [BackgroundItem] {
        let sources: [(URL, BackgroundItemKind)] = [
            (FileUtilities.library.appendingPathComponent("LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .globalDaemon)
        ]
        var items: [BackgroundItem] = []
        for (dir, kind) in sources {
            for url in FileUtilities.children(of: dir) where url.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: url),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
                else { continue }
                let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                items.append(BackgroundItem(plistURL: url, label: label, program: program,
                                            runAtLoad: plist["RunAtLoad"] as? Bool ?? false, kind: kind))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
}

// MARK: - Appcast parsing

private struct AppcastEntry {
    var shortVersion: String?
    var version: String?
    var url: URL?
}

private final class AppcastParser: NSObject, XMLParserDelegate {
    private var entries: [AppcastEntry] = []
    private var current: AppcastEntry?
    private var text = ""

    func parse(_ data: Data) -> [AppcastEntry] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return entries
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attrs: [String: String] = [:]) {
        text = ""
        switch name {
        case "item": current = AppcastEntry()
        case "enclosure":
            current?.url = attrs["url"].flatMap(URL.init(string:))
            if let v = attrs["sparkle:shortVersionString"] { current?.shortVersion = v }
            if let v = attrs["sparkle:version"] { current?.version = v }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "sparkle:shortVersionString": if !value.isEmpty { current?.shortVersion = value }
        case "sparkle:version": if !value.isEmpty { current?.version = value }
        case "item":
            if let c = current { entries.append(c) }
            current = nil
        default: break
        }
    }
}
