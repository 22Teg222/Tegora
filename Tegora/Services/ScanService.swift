import Foundation

struct Recommendation: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
    let target: SidebarSection?
}

enum HealthRating: String {
    case excellent = "Excellent"
    case good = "Good"
    case needsAttention = "Needs Attention"
}

struct SmartCareReport {
    var disk: DiskInfo?
    var memory: MemorySnapshot?
    var junk: [CategoryResult] = []
    var threats: [ThreatFinding] = []
    var security: SystemSecurityStatus?
    var malwareReady = false
    var malwareFilesScanned: Int?
    var recommendations: [Recommendation] = []
    var score = 100

    var junkBytes: Int64 { junk.reduce(0) { $0 + $1.totalSize } }
    var rating: HealthRating {
        score >= 90 ? .excellent : (score >= 70 ? .good : .needsAttention)
    }

    /// Junk categories that Smart Care may clean in one go, after the user reviews them.
    /// Language files, mail attachments and iOS backups are deliberately left to the Cleanup page.
    static let autoCleanCategories: [CleanupCategory] = [.systemCache, .logs, .temporary, .xcode, .trash, .brokenPreferences]

    var autoCleanResults: [CategoryResult] {
        junk.filter { Self.autoCleanCategories.contains($0.category) && !$0.items.isEmpty }
    }
}

enum ScanService {

    /// Runs every Smart Care check in order and reports real progress (0...1) with a description of the current step.
    static func runSmartScan(progress: @escaping @Sendable (String, Double) -> Void) async -> SmartCareReport {
        var report = SmartCareReport()
        let categories = CleanupCategory.allCases
        let steps = Double(categories.count + 5)
        var step = 0.0
        func advance(_ label: String) { progress(label, step / steps); step += 1 }

        advance("Reading storage…")
        report.disk = StorageService.startupDisk()

        advance("Reading memory…")
        report.memory = MemoryService.snapshot()

        for category in categories {
            if Task.isCancelled { break }
            advance("Looking for \(category.title.lowercased())…")
            let result = await Task.detached(priority: .utility) { CleanupService.scan(category) }.value
            report.junk.append(result)
        }

        // Malware: a quick ClamAV scan of the places malware usually lands (Downloads, Desktop, startup folders).
        advance("Preparing malware scan…")
        let clam = await Task.detached(priority: .utility) { MalwareService.state() }.value
        var malwareFindings: [ThreatFinding] = []
        if clam.isReady, !Task.isCancelled {
            report.malwareReady = true
            let session = StreamingProcess()
            let targets = MalwareService.quickTargets
            let base = step - 1
            let summary: MalwareScanSummary = await withTaskCancellationHandler {
                let total = await Task.detached(priority: .utility) {
                    MalwareService.countFiles(in: targets) { session.isCancelled }
                }.value
                return await MalwareService.scan(targets: targets, session: session) { n, path in
                    let fraction = (base + min(Double(n) / Double(max(total, 1)), 1)) / steps
                    progress("Scanning \((path as NSString).lastPathComponent)…", fraction)
                }
            } onCancel: { session.cancel() }
            if summary.failureMessage == nil && !summary.wasCancelled { report.malwareFilesScanned = summary.scannedFiles }
            malwareFindings = summary.detections.map {
                ThreatFinding(url: $0.url, kind: .malware, severity: .high,
                              explanation: "ClamAV identified this file as \($0.signature). Review it in Protection before removing it.")
            }
        }

        advance("Checking app signatures…")
        let signatures = await Task.detached(priority: .utility) {
            ProtectionService.scanApplicationSignatures { _ in }
        }.value

        advance("Reviewing background items…")
        let launch = await Task.detached(priority: .utility) { ProtectionService.scanLaunchItems() }.value
        let adware = await Task.detached(priority: .utility) { ProtectionService.scanAdwareHeuristics() }.value
        report.threats = (malwareFindings + signatures + launch + adware).sorted { $0.severity > $1.severity }
        report.security = await Task.detached { ProtectionService.systemStatus() }.value

        progress("Summarising…", 1)
        report.recommendations = recommendations(for: report)
        report.score = score(for: report)
        return report
    }

    private static func recommendations(for r: SmartCareReport) -> [Recommendation] {
        var list: [Recommendation] = []
        if r.junkBytes > 100 * 1_048_576 {
            list.append(Recommendation(symbol: "sparkles", title: "Clean \(Fmt.bytes(r.junkBytes)) of junk",
                                       detail: "Caches, logs and other files that can be safely recreated.", target: .cleanup))
        }
        if let d = r.disk, d.usedFraction > 0.85 {
            list.append(Recommendation(symbol: "internaldrive", title: "Your disk is \(Fmt.percent(d.usedFraction)) full",
                                       detail: "Use Space Lens to see which folders take the most room.", target: .spaceLens))
        }
        if let m = r.memory, m.usedFraction > 0.85 {
            list.append(Recommendation(symbol: "memorychip", title: "Memory is under pressure",
                                       detail: "Most of your RAM is in use. Closing apps you aren't using will help.", target: nil))
        }
        if r.threats.contains(where: { $0.severity >= .warning }) {
            list.append(Recommendation(symbol: "exclamationmark.shield", title: "Review security findings",
                                       detail: "Some apps or background items deserve a closer look.", target: .protection))
        }
        if !r.malwareReady {
            list.append(Recommendation(symbol: "shield.lefthalf.filled", title: "Turn on malware scanning",
                                       detail: "Set up ClamAV in Protection so Smart Care can look for known malware.", target: .protection))
        }
        if let s = r.security, s.firewallEnabled == false {
            list.append(Recommendation(symbol: "firewall", title: "The macOS firewall is off",
                                       detail: "You can turn it on in System Settings > Network > Firewall.", target: .protection))
        }
        return list
    }

    private static func score(for r: SmartCareReport) -> Int {
        var score = 100
        if let d = r.disk { score -= d.usedFraction > 0.9 ? 15 : (d.usedFraction > 0.8 ? 8 : 0) }
        score -= r.junkBytes > 5_000_000_000 ? 10 : (r.junkBytes > 1_000_000_000 ? 5 : 0)
        score -= min(r.threats.filter { $0.severity == .high }.count * 15, 30)
        score -= min(r.threats.filter { $0.severity == .warning }.count * 5, 15)
        if let s = r.security {
            if s.gatekeeperEnabled == false { score -= 10 }
            if s.sipEnabled == false { score -= 10 }
            if s.firewallEnabled == false { score -= 5 }
        }
        if let m = r.memory, m.usedFraction > 0.9 { score -= 5 }
        return max(score, 0)
    }
}
