import SwiftUI

struct ApplicationsView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case uninstaller = "Uninstaller", updater = "Updater"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .uninstaller
    @State private var apps: [InstalledApp] = []
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                PageHeader(title: "Applications", subtitle: "Uninstall apps cleanly and check for updates.",
                           symbol: "square.grid.2x2")
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 480)
            }
            .padding(.horizontal, 32).padding(.bottom, 14)
            Group {
                switch tab {
                case .uninstaller: UninstallerPane(apps: $apps, loading: loading, reload: load)
                case .updater: UpdaterPane(apps: apps, loading: loading)
                }
            }
            .tegoraGlass(cornerRadius: 22)
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .task { if apps.isEmpty { load() } }
    }

    private func load() {
        loading = true
        Task {
            apps = await Task.detached(priority: .userInitiated) { ApplicationService.installedApps() }.value
            loading = false
        }
    }
}

// MARK: - Uninstaller

private struct UninstallerPane: View {
    @Binding var apps: [InstalledApp]
    let loading: Bool
    let reload: () -> Void

    @State private var search = ""
    @State private var selection: Set<URL> = []
    @State private var preview: AppRemovalPreview?
    @State private var banner: OperationReport?
    @State private var sortBySize = false
    @State private var preparing = false

    private var visible: [InstalledApp] {
        let list = apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        return sortBySize ? list.sorted { $0.size > $1.size } : list
    }
    private var selectedApps: [InstalledApp] { apps.filter { selection.contains($0.url) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $search).textFieldStyle(.plain)
                Spacer()
                Picker("Sort", selection: $sortBySize) {
                    Text("Name").tag(false)
                    Text("Size").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 140).labelsHidden()
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            if let banner { ReportBanner(report: banner) { self.banner = nil }.padding(.horizontal, 24).padding(.bottom, 8) }
            Divider()
            if loading && apps.isEmpty {
                Spacer(); ProgressView("Reading applications…"); Spacer()
            } else {
                List(visible) { app in
                    AppRow(app: app, isSelected: selection.contains(app.url)) {
                        if selection.contains(app.url) { selection.remove(app.url) } else { selection.insert(app.url) }
                    }
                }
                .listStyle(.inset).scrollContentBackground(.hidden)
            }
            Divider()
            HStack {
                Text(selection.isEmpty ? "\(apps.count) apps" : "\(selection.count) selected · \(Fmt.bytes(selectedApps.reduce(0) { $0 + $1.size }))")
                    .foregroundStyle(.secondary)
                if preparing { ProgressView().controlSize(.small) }
                Spacer()
                Button { reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Button(selection.count > 1 ? "Review & Uninstall \(selection.count) Apps…" : "Review & Uninstall…") { prepare() }
                    .prominentGlassButton().disabled(selection.isEmpty || preparing)
            }
            .padding(.horizontal, 24).padding(.vertical, 12).background(Color.primary.opacity(0.04))
        }
        .sheet(item: $preview) { p in
            AppRemovalSheet(preview: p) { report in
                banner = report
                preview = nil
                selection = []
                reload()
            } onCancel: { preview = nil }
        }
    }

    private func prepare() {
        let chosen = selectedApps
        preparing = true
        Task {
            let entries = await Task.detached { () -> [AppRemovalPreview.Entry] in
                chosen.map { AppRemovalPreview.Entry(app: $0, leftovers: ApplicationService.leftovers(for: $0)) }
            }.value
            preview = AppRemovalPreview(entries: entries)
            preparing = false
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let isSelected: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        let isSystem = ApplicationService.isSystemApp(app)
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox).labelsHidden().disabled(isSystem)
            FileIconView(url: app.url, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text([app.version.map { "Version \($0)" }, app.isAppStore ? "App Store" : nil, isSystem ? "Apple" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.bytes(app.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { hovering = $0 }
        .onTapGesture { if !isSystem { toggle() } }
    }
}

struct AppRemovalPreview: Identifiable {
    struct Entry: Identifiable {
        let app: InstalledApp
        var leftovers: [FoundItem]
        var id: URL { app.url }
    }
    let id = UUID()
    var entries: [Entry]
}

private struct AppRemovalSheet: View {
    let preview: AppRemovalPreview
    let onFinish: (OperationReport) -> Void
    let onCancel: () -> Void
    @State private var keep: Set<URL> = []   // leftovers the user unticked
    @State private var working = false

    private func chosenLeftovers(_ e: AppRemovalPreview.Entry) -> [FoundItem] { e.leftovers.filter { !keep.contains($0.url) } }
    private var totalSize: Int64 {
        preview.entries.reduce(0) { $0 + $1.app.size + chosenLeftovers($1).reduce(0) { $0 + $1.size } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill").font(.title).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Uninstall \(preview.entries.count) app\(preview.entries.count == 1 ? "" : "s")?").font(.title3.weight(.semibold))
                    Text("About \(Fmt.bytes(totalSize)) will be moved to the Trash. You can restore it from there.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(preview.entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                FileIconView(url: entry.app.url, size: 28)
                                Text(entry.app.name).font(.headline)
                                if ApplicationService.isRunning(entry.app) {
                                    Label("Running", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                                }
                                Spacer()
                                Text(Fmt.bytes(entry.app.size)).foregroundStyle(.secondary)
                            }
                            if entry.leftovers.isEmpty {
                                Text("No leftover files found.").font(.caption).foregroundStyle(.secondary).padding(.leading, 36)
                            }
                            ForEach(entry.leftovers) { item in
                                Toggle(isOn: Binding(
                                    get: { !keep.contains(item.url) },
                                    set: { on in if on { keep.remove(item.url) } else { keep.insert(item.url) } }
                                )) {
                                    HStack {
                                        Text(item.url.friendlyPath).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Text(Fmt.bytes(item.size)).foregroundStyle(.secondary)
                                    }
                                    .font(.caption)
                                }
                                .toggleStyle(.checkbox).padding(.leading, 36)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 280)
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction).disabled(working)
                Button("Move to Trash") {
                    working = true
                    let entries = preview.entries.map { ($0.app, chosenLeftovers($0)) }
                    Task {
                        let report = await Task.detached { () -> OperationReport in
                            var total = OperationReport()
                            for (app, left) in entries { total.merge(ApplicationService.uninstall(app, leftovers: left)) }
                            return total
                        }.value
                        onFinish(report)
                    }
                }
                .prominentGlassButton().keyboardShortcut(.defaultAction).disabled(working)
            }
        }
        .padding(24).frame(width: 560)
    }
}

// MARK: - Updater

private struct UpdaterPane: View {
    let apps: [InstalledApp]
    let loading: Bool
    @State private var updates: [URL: AppUpdateInfo] = [:]
    @State private var checked: Set<URL> = []
    @State private var checking = false
    @State private var progress = 0.0
    @State private var done = false

    private var checkable: [InstalledApp] { apps.filter(ApplicationService.canCheckForUpdates) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Outdated apps").font(.headline)
                    Text("Checks \(checkable.count) of \(apps.count) apps: Mac App Store apps and apps that use Sparkle updates. Other apps update themselves or can't be checked.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if checking { ProgressView(value: progress).frame(width: 120) }
                Button { check() } label: { Label(done ? "Check Again" : "Check for Updates", systemImage: "arrow.triangle.2.circlepath") }
                    .prominentGlassButton().disabled(checking || loading || checkable.isEmpty)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            if !done && !checking {
                emptyState("arrow.triangle.2.circlepath", "Ready to check", "Tegora contacts Apple and each app's update server. No app data is sent.")
            } else if done && updates.isEmpty {
                emptyState("checkmark.circle", "Everything is up to date", "No newer versions were found.")
            } else {
                List(apps.filter { updates[$0.url] != nil }) { app in
                    if let info = updates[app.url] {
                        HStack(spacing: 12) {
                            FileIconView(url: app.url, size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                Text("\(app.version ?? "?") → \(info.latestVersion)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if app.isAppStore {
                                Button("Open in App Store") { if let u = info.downloadURL { NSWorkspace.shared.open(u) } }
                            } else {
                                Button("Download") { if let u = info.downloadURL { NSWorkspace.shared.open(u) } }
                                    .disabled(info.downloadURL == nil)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset).scrollContentBackground(.hidden)
            }
        }
    }

    private func emptyState(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(.secondary).symbolRenderingMode(.hierarchical)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private func check() {
        checking = true; updates = [:]; progress = 0
        let list = checkable
        Task {
            var found: [URL: AppUpdateInfo] = [:]
            for (i, app) in list.enumerated() {
                if let info = await ApplicationService.checkForUpdate(app) { found[app.url] = info }
                progress = Double(i + 1) / Double(max(list.count, 1))
            }
            updates = found
            checking = false
            done = true
        }
    }
}
