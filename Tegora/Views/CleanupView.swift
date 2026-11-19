import SwiftUI

struct CleanupView: View {
    @State private var results: [CleanupCategory: CategoryResult] = [:]
    @State private var scanning: Set<CleanupCategory> = []
    @State private var selected: CleanupCategory = .systemCache
    @State private var selections: [CleanupCategory: Set<URL>] = [:]
    @State private var removal: RemovalRequest?
    @State private var banner: OperationReport?
    @State private var scanTask: Task<Void, Never>?
    @State private var hasScanned = false

    private var isScanning: Bool { !scanning.isEmpty }
    private var totalSelectedItems: [(CleanupCategory, [FoundItem])] {
        CleanupCategory.allCases.compactMap { cat in
            guard let result = results[cat], let sel = selections[cat], !sel.isEmpty else { return nil }
            let items = result.items.filter { sel.contains($0.url) }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                PageHeader(title: "Cleanup", subtitle: "Review files before anything is removed.", symbol: "trash.slash")
                PermissionBanner()
                if let banner { ReportBanner(report: banner) { self.banner = nil } }
            }
            .padding(.horizontal, 32)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    categoryList.frame(width: 260)
                    Divider()
                    detail
                }
                Divider()
                footer
            }
            .tegoraGlass(cornerRadius: 22)
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 20)
        }
        .sheet(item: $removal) { request in
            ConfirmRemovalSheet(request: request) { report in
                banner = report
                removal = nil
                scan()
            } onCancel: { removal = nil }
        }
        .onDisappear { scanTask?.cancel() }
    }

    // MARK: Category list

    private var categoryList: some View {
        List(CleanupCategory.allCases, selection: Binding<CleanupCategory?>(
            get: { selected },
            set: { if let value = $0 { selected = value } }
        )) { cat in
            HStack(spacing: 10) {
                Image(systemName: cat.symbol).symbolRenderingMode(.hierarchical).foregroundStyle(.tint).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cat.title)
                    if let r = results[cat] {
                        Text("\(r.items.count) item\(r.items.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if scanning.contains(cat) {
                    ProgressView().controlSize(.small)
                } else if let r = results[cat] {
                    Text(Fmt.bytes(r.totalSize)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .tag(cat)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selected.title).font(.title2.weight(.semibold))
                Text(selected.detail).font(.callout).foregroundStyle(.secondary)
                if let warning = results[selected]?.warning {
                    Label(warning, systemImage: "info.circle").font(.caption).foregroundStyle(.orange).padding(.top, 2)
                }
            }
            .padding(20)
            Divider()
            if !hasScanned {
                placeholder(symbol: "magnifyingglass", title: "Ready to scan",
                            text: "Tegora will look through your Library, Xcode folders and Trash. Nothing is removed during a scan.")
            } else if scanning.contains(selected) {
                placeholder(symbol: "hourglass", title: "Scanning…", text: "Measuring \(selected.title.lowercased()).", spinner: true)
            } else if let result = results[selected], !result.items.isEmpty {
                ReviewList(items: result.items,
                           selection: Binding(get: { selections[selected] ?? [] }, set: { selections[selected] = $0 }))
            } else {
                placeholder(symbol: "checkmark.circle", title: "Nothing to clean", text: "No \(selected.title.lowercased()) were found.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(symbol: String, title: String, text: String, spinner: Bool = false) -> some View {
        VStack(spacing: 10) {
            Spacer()
            if spinner { ProgressView() } else {
                Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(.secondary).symbolRenderingMode(.hierarchical)
            }
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            let chosen = totalSelectedItems
            let count = chosen.reduce(0) { $0 + $1.1.count }
            let size = chosen.reduce(Int64(0)) { $0 + $1.1.reduce(0) { $0 + $1.size } }
            Button { scan() } label: {
                Label(hasScanned ? "Rescan" : "Scan", systemImage: "magnifyingglass")
            }
            .disabled(isScanning)
            if isScanning { ProgressView().controlSize(.small) }
            Spacer()
            Text(count == 0 ? "Nothing selected" : "\(count) items · \(Fmt.bytes(size))")
                .font(.callout).foregroundStyle(.secondary)
            Button("Review & Remove") { removal = makeRequest(chosen) }
                .prominentGlassButton()
                .disabled(count == 0 || isScanning)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    // MARK: Actions

    private func scan() {
        scanTask?.cancel()
        hasScanned = true
        results = [:]
        selections = [:]
        scanning = Set(CleanupCategory.allCases)
        scanTask = Task {
            for cat in CleanupCategory.allCases {
                let result = await Task.detached(priority: .utility) { CleanupService.scan(cat) }.value
                if Task.isCancelled { return }
                results[cat] = result
                scanning.remove(cat)
            }
        }
    }

    private func makeRequest(_ chosen: [(CleanupCategory, [FoundItem])]) -> RemovalRequest {
        let permanent = chosen.contains { $0.0.deletesPermanently }
        let note: String? = {
            var parts: [String] = []
            if chosen.contains(where: { $0.0 == .languages }) {
                parts.append("Removing language files modifies the apps themselves and may make macOS flag them as damaged. Reinstalling an app restores them.")
            }
            if chosen.contains(where: { $0.0 == .iosBackups }) {
                parts.append("iOS backups may be the only copy of your device data. Make sure you don't need them.")
            }
            if permanent { parts.append("Trash items are deleted permanently; everything else goes to the Trash.") }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }()
        return RemovalRequest(title: "Remove selected files", items: chosen.flatMap { $0.1 },
                              permanent: permanent, extraNote: note) { _ in
            await Task.detached {
                var total = OperationReport()
                for (cat, items) in chosen { total.merge(CleanupService.remove(items, category: cat)) }
                return total
            }.value
        }
    }
}
