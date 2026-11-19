import AppKit
import Foundation
import Security

enum ThreatSeverity: Int, Comparable {
    case info = 0, warning, high
    static func < (a: ThreatSeverity, b: ThreatSeverity) -> Bool { a.rawValue < b.rawValue }
}

enum ThreatKind: String {
    case invalidSignature = "Invalid code signature"
    case unsignedApp = "Unsigned app"
    case suspiciousLaunchItem = "Suspicious background item"
    case adwareHeuristic = "Possible adware"
    case notNotarized = "Not notarized"
    case malware = "Malware detected"
}

struct ThreatFinding: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let kind: ThreatKind
    let severity: ThreatSeverity
    let explanation: String
}

struct SystemSecurityStatus {
    let gatekeeperEnabled: Bool?
    let sipEnabled: Bool?
    let firewallEnabled: Bool?
}

/// Malware detection itself is done by ClamAV (see MalwareService). This service covers what macOS can verify
/// natively: code signatures and notarization (Security framework and Gatekeeper), startup items that run from
/// unusual places, and the state of Gatekeeper, SIP and the firewall. Findings are things to review, not verdicts.
enum ProtectionService {

    // MARK: System status

    static func systemStatus() -> SystemSecurityStatus {
        SystemSecurityStatus(
            gatekeeperEnabled: run("/usr/sbin/spctl", ["--status"]).map { $0.contains("enabled") },
            sipEnabled: run("/usr/bin/csrutil", ["status"]).map { $0.contains("enabled") },
            firewallEnabled: run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
                .map { $0.contains("enabled") }
        )
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.lowercased()
    }

    // MARK: Scans

    /// Verifies the code signature of every third-party app. Blocking.
    static func scanApplicationSignatures(progress: (String) -> Void) -> [ThreatFinding] {
        var findings: [ThreatFinding] = []
        let dirs = [URL(fileURLWithPath: "/Applications"), FileUtilities.home.appendingPathComponent("Applications")]
        for dir in dirs {
            for app in FileUtilities.children(of: dir) where app.pathExtension == "app" {
                if Task.isCancelled { return findings }
                progress(app.deletingPathExtension().lastPathComponent)
                switch signatureState(of: app) {
                case .valid:
                    if case .rejected(let source) = gatekeeperVerdict(of: app) {
                        findings.append(ThreatFinding(url: app, kind: .notNotarized, severity: .info,
                            explanation: "Gatekeeper wouldn't approve this app (\(source)). It is signed, but Apple hasn't notarized it. That's common for older apps and open-source tools, so only keep it if you trust where it came from."))
                    }
                case .unsigned:
                    findings.append(ThreatFinding(url: app, kind: .unsignedApp, severity: .warning,
                        explanation: "This app has no code signature, so macOS can't verify who made it or whether it was modified. Many legitimate open-source apps are unsigned; only keep it if you trust where it came from."))
                case .invalid(let message):
                    findings.append(ThreatFinding(url: app, kind: .invalidSignature, severity: .high,
                        explanation: "The signature doesn't match the app's contents (\(message)). The app may have been modified after it was signed, or damaged."))
                }
            }
        }
        return findings
    }

    enum GatekeeperVerdict { case accepted(source: String), rejected(source: String), unknown }

    /// Asks Gatekeeper (spctl) whether it would run this app, and why.
    static func gatekeeperVerdict(of url: URL) -> GatekeeperVerdict {
        guard let output = run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", url.path]) else { return .unknown }
        let source = output.components(separatedBy: "\n").first { $0.hasPrefix("source=") }
            .map { String($0.dropFirst(7)) } ?? "no reason given"
        if output.contains(": accepted") { return .accepted(source: source) }
        if output.contains(": rejected") { return .rejected(source: source) }
        return .unknown
    }

    enum SignatureState { case valid, unsigned, invalid(String) }

    static func signatureState(of url: URL) -> SignatureState {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return .invalid("couldn't read the app") }
        let status = SecStaticCodeCheckValidityWithErrors(code, SecCSFlags(rawValue: 0), nil, nil)
        let code32 = Int(status)
        if code32 == Int(errSecSuccess) { return .valid }
        if code32 == Int(errSecCSUnsigned) { return .unsigned }
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(code32)"
        return .invalid(message)
    }

    /// Looks at launch agents and daemons for ones that run from places legitimate software rarely uses.
    static func scanLaunchItems() -> [ThreatFinding] {
        var findings: [ThreatFinding] = []
        for item in ApplicationService.backgroundItems() {
            guard let program = item.program else { continue }
            let lower = program.lowercased()
            let odd = lower.hasPrefix("/tmp/") || lower.hasPrefix("/private/tmp/") || lower.hasPrefix("/var/tmp/")
                || lower.contains("/downloads/") || lower.contains("/.") // hidden folders
            if odd {
                findings.append(ThreatFinding(url: item.plistURL, kind: .suspiciousLaunchItem, severity: .high,
                    explanation: "\"\(item.label)\" starts automatically and runs a program from \(program). Legitimate software normally installs into /Applications or /Library, not temporary, hidden or Downloads folders."))
            } else if !FileManager.default.fileExists(atPath: program) {
                findings.append(ThreatFinding(url: item.plistURL, kind: .suspiciousLaunchItem, severity: .info,
                    explanation: "\"\(item.label)\" points to a program that no longer exists (\(program)). This is usually left over from an uninstalled app and is harmless, but can be removed."))
            }
        }
        return findings
    }

    /// Flags apps whose names match widely documented unwanted-software families. This is a name check only,
    /// it can't confirm that anything is malicious, so results are worded as "possible".
    static func scanAdwareHeuristics() -> [ThreatFinding] {
        let knownNames = ["mackeeper", "advancedmaccleaner", "mac auto fixer", "maccleanerpro",
                          "searchbaron", "genieo", "installmac", "mplayerx adware"]
        var findings: [ThreatFinding] = []
        let dirs = [URL(fileURLWithPath: "/Applications"), FileUtilities.home.appendingPathComponent("Applications")]
        for dir in dirs {
            for app in FileUtilities.children(of: dir) where app.pathExtension == "app" {
                let name = app.deletingPathExtension().lastPathComponent.lowercased()
                if knownNames.contains(where: { name.contains($0) }) {
                    findings.append(ThreatFinding(url: app, kind: .adwareHeuristic, severity: .warning,
                        explanation: "The name matches software that security vendors commonly classify as unwanted. Tegora can't verify this, so review it and remove it if you didn't intentionally install it."))
                }
            }
        }
        return findings
    }

    // MARK: Privacy data

    struct PrivacyTarget: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let paths: [URL]
        let browserBundleID: String?
    }

    static func privacyTargets() -> [PrivacyTarget] {
        let lib = FileUtilities.library
        return [
            PrivacyTarget(id: "safari-history", title: "Safari History", symbol: "safari",
                          paths: [lib.appendingPathComponent("Safari/History.db"),
                                  lib.appendingPathComponent("Safari/History.db-wal"),
                                  lib.appendingPathComponent("Safari/History.db-shm")],
                          browserBundleID: "com.apple.Safari"),
            PrivacyTarget(id: "safari-cookies", title: "Safari Cookies", symbol: "circle.hexagongrid",
                          paths: [lib.appendingPathComponent("Cookies/Cookies.binarycookies"),
                                  lib.appendingPathComponent("Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")],
                          browserBundleID: "com.apple.Safari"),
            PrivacyTarget(id: "chrome-history", title: "Chrome History", symbol: "globe",
                          paths: chromeFiles(["History", "History-journal"]),
                          browserBundleID: "com.google.Chrome"),
            PrivacyTarget(id: "chrome-cookies", title: "Chrome Cookies", symbol: "circle.hexagongrid",
                          paths: chromeFiles(["Cookies", "Cookies-journal", "Network/Cookies"]),
                          browserBundleID: "com.google.Chrome"),
            PrivacyTarget(id: "firefox", title: "Firefox History & Cookies", symbol: "flame",
                          paths: firefoxFiles(["places.sqlite", "cookies.sqlite"]),
                          browserBundleID: "org.mozilla.firefox"),
            PrivacyTarget(id: "recent-items", title: "Recent Items Lists", symbol: "clock",
                          paths: [lib.appendingPathComponent("Application Support/com.apple.sharedfilelist")],
                          browserBundleID: nil)
        ]
    }

    private static func chromeFiles(_ names: [String]) -> [URL] {
        let root = FileUtilities.library.appendingPathComponent("Application Support/Google/Chrome")
        let profiles = FileUtilities.children(of: root).filter {
            $0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile ")
        }
        return profiles.flatMap { p in names.map { p.appendingPathComponent($0) } }
    }

    private static func firefoxFiles(_ names: [String]) -> [URL] {
        let root = FileUtilities.library.appendingPathComponent("Application Support/Firefox/Profiles")
        return FileUtilities.children(of: root).flatMap { p in names.map { p.appendingPathComponent($0) } }
    }

    static func existingItems(for target: PrivacyTarget) -> [FoundItem] {
        target.paths.compactMap { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return FoundItem(url: url, size: FileUtilities.size(of: url), modified: FileUtilities.modificationDate(url))
        }
    }

    static func isRunning(_ target: PrivacyTarget) -> Bool {
        guard let id = target.browserBundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    /// Browser data is deleted permanently: moving a live cookie database to the Trash would keep the data.
    static func clear(_ items: [FoundItem]) -> OperationReport {
        var report = OperationReport()
        for item in items {
            if let error = FileUtilities.permanentlyDelete(item.url) {
                report.errors.append(error)
            } else {
                report.removedCount += 1
                report.freedBytes += item.size
            }
        }
        return report
    }

    // MARK: System Settings

    static let fullDiskAccessURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    static func openSettings(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
