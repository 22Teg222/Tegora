import SwiftUI

struct SmartCareView: View {
    @EnvironmentObject private var model: SmartCareModel
    @EnvironmentObject private var navigation: Navigation
    @Environment(\.sectionTheme) private var theme
    @State private var removal: RemovalRequest?
    @State private var banner: OperationReport?
    @State private var reviewing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                PageHeader(title: "Smart Care", subtitle: "One scan to check your whole Mac.", symbol: "sparkles")
                hero
                if let banner { ReportBanner(report: banner) { self.banner = nil } }
                overview
                if let report = model.report { findings(report) }
            }
            .padding(.horizontal, 32).padding(.bottom, 36)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $removal) { request in
            ConfirmRemovalSheet(request: request) { report in
                banner = report
                removal = nil
                model.startScan()
            } onCancel: { removal = nil }
        }
        .sheet(isPresented: $reviewing) {
            if let report = model.report {
                AutoCleanReviewSheet(results: report.autoCleanResults) { chosen in
                    reviewing = false
                    if !chosen.isEmpty { removal = makeRequest(chosen) }
                }
            }
        }
        .onAppear { model.refreshLive() }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 20) {
            ZStack {
                ProgressRing(fraction: ringFraction, lineWidth: 12, tint: ringTint)
                    .frame(width: 250, height: 250)
                Button { model.startScan() } label: { disc }
                    .buttonStyle(.plain)
                    .disabled(model.isScanning)
            }
            .padding(.top, 6)

            VStack(spacing: 6) {
                Text(heroTitle).font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(heroSubtitle).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
            }

            HStack(spacing: 12) {
                if model.isScanning {
                    Button("Stop") { model.cancelScan() }.glassButton().controlSize(.large)
                } else if model.report == nil {
                    Button { model.startScan() } label: {
                        Label("Start Scan", systemImage: "magnifyingglass").frame(minWidth: 110)
                    }
                    .prominentGlassButton().controlSize(.large)
                } else {
                    if let report = model.report, !report.autoCleanResults.isEmpty {
                        Button { reviewing = true } label: {
                            Label("Review & Clean \(Fmt.bytes(report.autoCleanResults.reduce(0) { $0 + $1.totalSize }))",
                                  systemImage: "sparkles")
                        }
                        .prominentGlassButton().controlSize(.large)
                    }
                    Button { model.startScan() } label: { Label("Scan Again", systemImage: "arrow.clockwise") }
                        .glassButton().controlSize(.large)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var disc: some View {
        VStack(spacing: 4) {
            if let report = model.report, !model.isScanning {
                Text("\(report.score)").font(.system(size: 58, weight: .bold, design: .rounded)).monospacedDigit()
                Text(report.rating.rawValue).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            } else if model.isScanning {
                Text(Fmt.percent(model.progress)).font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit()
                Text("Scanning").font(.callout.weight(.medium)).foregroundStyle(.secondary)
            } else {
                Image(systemName: "leaf.fill").font(.system(size: 56))
                    .foregroundStyle(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolRenderingMode(.monochrome)
                Text("Scan").font(.title3.weight(.semibold))
            }
        }
        .frame(width: 196, height: 196)
        .tegoraGlassCircle(interactive: !model.isScanning)
        .contentShape(Circle())
    }

    private var ringFraction: Double {
        if model.isScanning { return model.progress }
        if let r = model.report { return Double(r.score) / 100 }
        return 0
    }

    private var ringTint: Color {
        guard !model.isScanning, let r = model.report else { return theme.accent }
        switch r.rating {
        case .excellent: return .green
        case .good: return theme.accent
        case .needsAttention: return .orange
        }
    }

    private var heroTitle: String {
        if case .running(let label) = model.phase { return label }
        guard let r = model.report else { return "Ready when you are" }
        switch r.rating {
        case .excellent: return "Your Mac is in great shape"
        case .good: return "Your Mac is doing well"
        case .needsAttention: return "Your Mac needs some attention"
        }
    }

    private var heroSubtitle: String {
        if model.isScanning { return "Checking storage, junk files, malware, app signatures and system protections." }
        guard let r = model.report else {
            return "Smart Care reads real storage and memory numbers, looks for junk and reviews security. Nothing is removed until you approve it."
        }
        return "\(Fmt.bytes(r.junkBytes)) of removable files found · \(r.threats.count) item\(r.threats.count == 1 ? "" : "s") to review"
    }

    // MARK: Overview

    private var overview: some View {
        let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]
        return LazyVGrid(columns: columns, spacing: 16) {
            if let d = model.disk {
                GlassCard(hoverEffect: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            IconBadge(symbol: "internaldrive", colors: [.blue, .cyan], size: 30)
                            Text("Storage").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        Text("\(Fmt.bytes(d.available)) free").font(.system(size: 22, weight: .semibold, design: .rounded))
                        MeterBar(fraction: d.usedFraction, tint: d.usedFraction > 0.9 ? .orange : .blue)
                        Text("\(Fmt.bytes(d.used)) of \(Fmt.bytes(d.total)) used").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onTapGesture { navigation.selection = .spaceLens }
            }
            if let m = model.memory {
                GlassCard(hoverEffect: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            IconBadge(symbol: "memorychip", colors: [.purple, .pink], size: 30)
                            Text("Memory").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        Text("\(Fmt.bytes(m.available)) available").font(.system(size: 22, weight: .semibold, design: .rounded))
                        MeterBar(fraction: m.usedFraction, tint: m.usedFraction > 0.85 ? .orange : .purple)
                        Text("\(Fmt.bytes(m.used)) of \(Fmt.bytes(m.total)) in use").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            StatTile(symbol: "sparkles", title: "Cleanup",
                     value: model.report.map { Fmt.bytes($0.junkBytes) } ?? "Not scanned",
                     detail: model.report == nil ? "Run a scan to find junk" : "Ready to review and remove",
                     colors: [.teal, .green])
                .onTapGesture { navigation.selection = .cleanup }
            securityTile
                .onTapGesture { navigation.selection = .protection }
        }
    }

    private var securityTile: some View {
        let status = model.report?.security
        let issues = model.report?.threats.filter { $0.severity >= .warning }.count
        var value = "Not scanned"
        var detail = "Run a scan to check security"
        var tint: Color? = nil
        if let report = model.report, let issues {
            value = issues == 0 ? "No issues" : "\(issues) to review"
            tint = issues == 0 ? .green : .orange
            let off = [status?.gatekeeperEnabled == false ? "Gatekeeper" : nil,
                       status?.firewallEnabled == false ? "Firewall" : nil].compactMap { $0 }
            if let scanned = report.malwareFilesScanned {
                detail = "\(scanned.formatted()) files checked for malware"
            } else if !report.malwareReady {
                detail = "Malware scan isn't set up yet"
            } else {
                detail = "macOS protections look healthy"
            }
            if !off.isEmpty { detail = "\(off.joined(separator: ", ")) off" }
        }
        return StatTile(symbol: "checkmark.shield", title: "Protection", value: value, detail: detail,
                        colors: [.green, .mint], tint: tint)
    }

    // MARK: Findings

    private func findings(_ report: SmartCareReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendations").font(.title3.weight(.semibold))
            if report.recommendations.isEmpty {
                GlassCard {
                    Label("Nothing needs your attention right now.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                ForEach(report.recommendations) { rec in
                    Button {
                        if let target = rec.target { navigation.selection = target }
                    } label: {
                        GlassCard(padding: 14, hoverEffect: rec.target != nil) {
                            HStack(spacing: 14) {
                                IconBadge(symbol: rec.symbol, colors: theme.colors, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rec.title).font(.headline)
                                    Text(rec.detail).font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if rec.target != nil { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func makeRequest(_ chosen: [(CleanupCategory, [FoundItem])]) -> RemovalRequest {
        let all = chosen.flatMap { $0.1 }
        let hasPermanent = chosen.contains { $0.0.deletesPermanently }
        return RemovalRequest(
            title: "Clean up your Mac", items: all, permanent: hasPermanent,
            extraNote: hasPermanent ? "Items already in the Trash will be deleted permanently. Everything else goes to the Trash." : nil
        ) { _ in
            await Task.detached {
                var total = OperationReport()
                for (category, items) in chosen { total.merge(CleanupService.remove(items, category: category)) }
                return total
            }.value
        }
    }
}

/// Smart Care's review step: pick which scanned categories to clean.
struct AutoCleanReviewSheet: View {
    let results: [CategoryResult]
    let onDone: ([(CleanupCategory, [FoundItem])]) -> Void
    @State private var enabled: Set<CleanupCategory> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review before cleaning").font(.title2.weight(.semibold))
            Text("Choose the categories to clean. You'll see the full list of files on the next screen. Language files, Mail attachments and iOS backups are only available in Cleanup.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(results) { result in
                Toggle(isOn: Binding(
                    get: { enabled.contains(result.category) },
                    set: { on in if on { enabled.insert(result.category) } else { enabled.remove(result.category) } }
                )) {
                    HStack {
                        Label(result.category.title, systemImage: result.category.symbol)
                        Spacer()
                        Text("\(result.items.count) items · \(Fmt.bytes(result.totalSize))").foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDone([]) }.keyboardShortcut(.cancelAction)
                Button("Continue") {
                    onDone(results.filter { enabled.contains($0.category) }.map { ($0.category, $0.items) })
                }
                .prominentGlassButton().keyboardShortcut(.defaultAction).disabled(enabled.isEmpty)
            }
        }
        .padding(24).frame(width: 480)
    }
}
