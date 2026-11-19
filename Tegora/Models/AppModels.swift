import AppKit
import Foundation

struct InstalledApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    let build: String?
    let size: Int64
    let isAppStore: Bool
    let sparkleFeed: URL?

    var id: URL { url }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

struct AppUpdateInfo: Hashable {
    let latestVersion: String
    let downloadURL: URL?
}

enum BackgroundItemKind: String {
    case userAgent = "User Agent"
    case globalAgent = "Global Agent"
    case globalDaemon = "Global Daemon"
}

struct BackgroundItem: Identifiable, Hashable {
    let plistURL: URL
    let label: String
    let program: String?
    let runAtLoad: Bool
    let kind: BackgroundItemKind

    var id: URL { plistURL }
}

struct MemorySnapshot {
    let total: Int64
    let used: Int64
    let available: Int64
    let app: Int64
    let wired: Int64
    let compressed: Int64
    let cached: Int64

    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}
