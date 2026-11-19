import SwiftUI

struct ProtectionView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case malware = "Malware", security = "Security Check", privacy = "Privacy"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .malware

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                PageHeader(title: "Protection", subtitle: "Malware scanning, security checks and privacy cleanup.", symbol: "checkmark.shield")
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
            }
            .padding(.horizontal, 32).padding(.bottom, 14)
            Group {
                switch tab {
                case .malware: MalwarePane()
                case .security: SecurityScanPane()
                case .privacy: PrivacyPane()
                }
            }
            .id(tab)
            .transition(.opacity)
        }
        .animation(.smooth(duration: 0.2), value: tab)
    }
}

// MARK: - Security scan

private struct SecurityScanPane: View {
    @State private var status: SystemSecurityStatus?
    @State private var findings: [ThreatFinding] = []
    @State private var scanning = false
    @State private var currentApp = ""
    @State private var scanned = false
    @State private var removal: RemovalRequest?
    @State private var banner: OperationReport?
    @State private var task: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                honestyNote
                statusCard
                if let banner { ReportBanner(report: banner) { self.banner = nil } }
                scanCard
                if scanned && !scanning { resultsSection }
            }
            .padding(32).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .task { status = await Task.detached { ProtectionService.systemStatus() }.value }
        .onDisappear { task?.cancel() }
        .sheet(item: $removal) { request in
            ConfirmRemovalSheet(request: request) { report in
                banner = report
                removal = nil
                scan()
            } onCancel: { removal = nil }
        }
    }

    private var honestyNote: some View {
        GlassCard(padding: 14) {
            Label {
                Text("This checks what macOS itself can verify: app code signatures and notarization, startup items that run from unusual places, and whether Gatekeeper, System Integrity Protection and the firewall are on. These are things to review, not proof of malware. Use the Malware tab to scan for known threats.")
                    .font(.callout).foregroundStyle(.secondary)
            } icon: { Image(systemName: "info.circle").foregroundStyle(.tint) }
        }
    }

    private var statusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("macOS protections").font(.headline)
                statusRow("Gatekeeper", "Checks that downloaded apps come from identified developers", status?.gatekeeperEnabled)
                statusRow("System Integrity Protection", "Prevents changes to protected system files", status?.sipEnabled)
                statusRow("Firewall", "Blocks unwanted incoming connections", status?.firewallEnabled)
            }
        }
    }

    private func statusRow(_ title: String, _ detail: String, _ on: Bool?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: on == true ? "checkmark.circle.fill" : (on == false ? "xmark.circle.fill" : "questionmark.circle"))
                .foregroundStyle(on == true ? .green : (on == false ? .orange : .secondary)).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(on == true ? "On" : (on == false ? "Off" : "Unknown")).foregroundStyle(.secondary)
        }
    }

    private var scanCard: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("App & startup item check").font(.headline)
                    Text(scanning ? "Checking \(currentApp)…" : "Verifies app signatures and notarization, and reviews launch agents and daemons.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if scanning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { task?.cancel(); scanning = false }
                } else {
                    Button { scan() } label: { Label(scanned ? "Scan Again" : "Scan", systemImage: "magnifyingglass") }
                        .prominentGlassButton()
                }
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if findings.isEmpty {
            GlassCard {
                Label("No issues found. All scanned apps have valid signatures and no unusual startup items were seen.",
                      systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(findings.count) item\(findings.count == 1 ? "" : "s") to review").font(.title3.weight(.semibold))
                ForEach(findings) { f in
                    GlassCard(padding: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            FileIconView(url: f.url, size: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(f.url.deletingPathExtension().lastPathComponent).font(.headline)
                                    severityBadge(f.severity, f.kind.rawValue)
                                }
                                Text(f.explanation).font(.callout).foregroundStyle(.secondary)
                                HStack {
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
                                    Button("Move to Trash…") { removal = request(for: f) }
                                }
                                .controlSize(.small).padding(.top, 2)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func severityBadge(_ s: ThreatSeverity, _ text: String) -> some View {
        let color: Color = s == .high ? .red : (s == .warning ? .orange : .secondary)
        return Text(text).font(.caption2.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18))).foregroundStyle(color)
    }

    private func scan() {
        scanning = true
        findings = []
        task = Task {
            let result = await Task.detached(priority: .utility) { () -> [ThreatFinding] in
                let sigs = ProtectionService.scanApplicationSignatures { name in
                    Task { @MainActor in currentApp = name }
                }
                return sigs + ProtectionService.scanLaunchItems() + ProtectionService.scanAdwareHeuristics()
            }.value
            if Task.isCancelled { return }
            findings = result.sorted { $0.severity > $1.severity }
            scanned = true
            scanning = false
        }
    }

    private func request(for f: ThreatFinding) -> RemovalRequest {
        let size = FileUtilities.size(of: f.url)
        let item = FoundItem(url: f.url, size: size, modified: FileUtilities.modificationDate(f.url))
        let isApp = f.url.pathExtension == "app"
        return RemovalRequest(title: "Remove \(f.url.deletingPathExtension().lastPathComponent)?", items: [item], permanent: false,
                              extraNote: isApp ? nil : "This stops the item from starting automatically.") { items in
            await Task.detached {
                var report = OperationReport()
                for i in items {
                    if let error = FileUtilities.moveToTrash(i.url) { report.errors.append(error) }
                    else { report.removedCount += 1; report.freedBytes += i.size }
                }
                return report
            }.value
        }
    }
}

// MARK: - Privacy

private struct PrivacyPane: View {
    @State private var targets = ProtectionService.privacyTargets()
    @State private var found: [String: [FoundItem]] = [:]
    @State private var chosen: Set<String> = []
    @State private var removal: RemovalRequest?
    @State private var banner: OperationReport?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard(padding: 14) {
                    Label("Browsers must be closed before their data can be cleared. Clearing history and cookies signs you out of websites. This is permanent.",
                          systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                }
                PermissionBanner()
                if let banner { ReportBanner(report: banner) { self.banner = nil } }
                ForEach(targets) { target in row(target) }
                HStack {
                    Button { reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    Spacer()
                    Button("Review & Clear") { removal = makeRequest() }
                        .prominentGlassButton().disabled(chosen.isEmpty)
                }
            }
            .padding(32).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .onAppear { reload() }
        .sheet(item: $removal) { request in
            ConfirmRemovalSheet(request: request) { report in
                banner = report; removal = nil; chosen = []; reload()
            } onCancel: { removal = nil }
        }
    }

    private func row(_ target: ProtectionService.PrivacyTarget) -> some View {
        let items = found[target.id] ?? []
        let running = ProtectionService.isRunning(target)
        let size = items.reduce(Int64(0)) { $0 + $1.size }
        return GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { chosen.contains(target.id) },
                    set: { on in if on { chosen.insert(target.id) } else { chosen.remove(target.id) } }
                ))
                .toggleStyle(.checkbox).labelsHidden().disabled(items.isEmpty || running)
                Image(systemName: target.symbol).font(.title3).foregroundStyle(.tint).frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.title)
                    Text(running ? "Quit the browser to clear this"
                         : (items.isEmpty ? "Nothing found" : "\(items.count) file\(items.count == 1 ? "" : "s")"))
                        .font(.caption).foregroundStyle(running ? .orange : .secondary)
                }
                Spacer()
                Text(items.isEmpty ? "" : Fmt.bytes(size)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .opacity(items.isEmpty ? 0.6 : 1)
    }

    private func reload() {
        targets = ProtectionService.privacyTargets()
        var map: [String: [FoundItem]] = [:]
        for t in targets { map[t.id] = ProtectionService.existingItems(for: t) }
        found = map
        chosen = chosen.filter { !(map[$0] ?? []).isEmpty }
    }

    private func makeRequest() -> RemovalRequest {
        let items = chosen.flatMap { found[$0] ?? [] }
        return RemovalRequest(title: "Clear privacy data", items: items, permanent: true,
                              extraNote: "You will be signed out of websites in the affected browsers.") { items in
            await Task.detached { ProtectionService.clear(items) }.value
        }
    }
}
