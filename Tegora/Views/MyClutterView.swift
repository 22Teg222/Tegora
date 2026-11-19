import SwiftUI
import UniformTypeIdentifiers

struct MyClutterView: View {
    private enum Tool: String, CaseIterable, Identifiable {
        case large = "Large Files", old = "Old Files", downloads = "Downloads"
        case duplicates = "Duplicates", similar = "Similar Images", analysis = "File Sizes"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .large: return "arrow.up.left.and.arrow.down.right"
            case .old: return "clock"
            case .downloads: return "arrow.down.circle"
            case .duplicates: return "doc.on.doc"
            case .similar: return "photo.on.rectangle"
            case .analysis: return "chart.bar"
            }
        }
        var blurb: String {
            switch self {
            case .large: return "Files of 100 MB or more."
            case .old: return "Files over a year old and at least 1 MB, judged by last opened or modified date."
            case .downloads: return "Everything in your Downloads folder, oldest first."
            case .duplicates: return "Files with byte-for-byte identical contents (SHA-256), 100 KB or larger."
            case .similar: return "Photos that look alike, found with Apple's Vision framework. Review each group; Tegora never picks for you."
            case .analysis: return "What kinds of files take up space in the scanned folders."
            }
        }
    }

    @Environment(\.sectionTheme) private var theme
    @State private var tool: Tool = .large
    @State private var roots: [URL] = ClutterService.defaultRoots
    @State private var catalog: [CatalogEntry] = []
    @State private var catalogProgress = 0
    @State private var cataloging = false
    @State private var cataloged = false

    @State private var items: [FoundItem] = []
    @State private var groups: [DuplicateGroup] = []
    @State private var breakdown: [KindBreakdown] = []
    @State private var selection: Set<URL> = []
    @State private var working = false
    @State private var workLabel = ""
    @State private var workProgress = 0.0
    @State private var removal: RemovalRequest?
    @State private var banner: OperationReport?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                PageHeader(title: "My Clutter", subtitle: "Find files you no longer need.", symbol: "square.stack.3d.up")
                toolPicker
                if let banner { ReportBanner(report: banner) { self.banner = nil } }
            }
            .padding(.horizontal, 32).padding(.bottom, 12)
            VStack(spacing: 0) {
                content
                Divider()
                footer
            }
            .tegoraGlass(cornerRadius: 22)
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .sheet(item: $removal) { request in
            ConfirmRemovalSheet(request: request) { report in
                banner = report
                removal = nil
                selection = []
                rebuildAfterRemoval(report)
            } onCancel: { removal = nil }
        }
        .onChange(of: tool) { _, _ in
            selection = []
            // Only reuse an existing scan; a first scan always starts from the Start Scan button.
            if cataloged || tool == .downloads { compute() }
        }
        .onDisappear { task?.cancel() }
    }

    private var toolPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Tool.allCases) { t in
                    Button { withAnimation(.smooth(duration: 0.2)) { tool = t } } label: {
                        Label(t.rawValue, systemImage: t.symbol)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(tool == t ? theme.accent.opacity(0.25) : Color.primary.opacity(0.06)))
                            .foregroundStyle(tool == t ? theme.accent : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tool.blurb).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if tool != .downloads {
                    Menu {
                        ForEach(roots, id: \.self) { Text($0.friendlyPath) }
                        Divider()
                        Button("Choose Folders…") { chooseFolders() }
                        Button("Reset to Defaults") { roots = ClutterService.defaultRoots; cataloged = false; compute() }
                    } label: { Label("\(roots.count) folders", systemImage: "folder") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            Divider()
            if working || cataloging {
                VStack(spacing: 12) {
                    Spacer()
                    if cataloging {
                        ProgressView()
                        Text("Reading files… \(catalogProgress) found").foregroundStyle(.secondary)
                    } else {
                        ProgressView(value: workProgress).frame(width: 240)
                        Text(workLabel).foregroundStyle(.secondary)
                    }
                    Button("Stop") { task?.cancel(); working = false; cataloging = false }
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else if !cataloged && tool != .downloads {
                prompt
            } else {
                results
            }
        }
    }

    private var prompt: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: tool.symbol).font(.system(size: 36)).foregroundStyle(.secondary)
            Text("Scan \(roots.count) folders").font(.headline)
            Text("Tegora reads file names, sizes and dates. File contents are read only to find duplicates and similar images, and nothing leaves your Mac.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            Button("Start Scan") { compute() }.prominentGlassButton().controlSize(.large)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var results: some View {
        switch tool {
        case .large, .old, .downloads:
            if items.isEmpty { empty } else {
                ReviewList(items: items, selection: $selection, showThumbnails: true)
            }
        case .duplicates, .similar:
            if groups.isEmpty { empty } else { groupList }
        case .analysis:
            if breakdown.isEmpty { empty } else { analysis }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("Nothing found").font(.headline)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var groupList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(groups) { group in
                    GlassCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(tool == .duplicates
                                     ? "\(group.items.count) identical copies · \(Fmt.bytes(group.wastedBytes)) wasted"
                                     : "\(group.items.count) similar images")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if tool == .duplicates {
                                    Button("Select Extras") {
                                        // Keep the first copy (shortest path), tick the rest.
                                        let sorted = group.items.sorted { $0.url.path.count < $1.url.path.count }
                                        sorted.dropFirst().forEach { selection.insert($0.url) }
                                        selection.remove(sorted[0].url)
                                    }
                                    .controlSize(.small)
                                }
                            }
                            ForEach(group.items) { item in
                                ReviewRow(item: item, isSelected: selection.contains(item.url), showThumbnail: true, showNote: false) {
                                    if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private var analysis: some View {
        let total = max(breakdown.reduce(0) { $0 + $1.size }, 1)
        return ScrollView {
            VStack(spacing: 12) {
                ForEach(breakdown) { row in
                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(row.kind, systemImage: row.symbol).font(.headline)
                                Spacer()
                                Text("\(row.count) files · \(Fmt.bytes(row.size))").foregroundStyle(.secondary).monospacedDigit()
                            }
                            MeterBar(fraction: Double(row.size) / Double(total))
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: Footer

    private var footer: some View {
        let selectedItems = allItems.filter { selection.contains($0.url) }
        return HStack {
            if cataloged || tool == .downloads {
                Button { cataloged = false; compute() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .disabled(working || cataloging)
            }
            Spacer()
            Text(selectedItems.isEmpty ? "Nothing selected"
                 : "\(selectedItems.count) files · \(Fmt.bytes(selectedItems.reduce(0) { $0 + $1.size }))")
                .foregroundStyle(.secondary)
            Button("Review & Move to Trash") {
                removal = RemovalRequest(title: "Move selected files to the Trash", items: selectedItems, permanent: false) { items in
                    await Task.detached { ClutterService.remove(items) }.value
                }
            }
            .prominentGlassButton().disabled(selectedItems.isEmpty)
        }
        .padding(.horizontal, 24).padding(.vertical, 12).background(Color.primary.opacity(0.04))
    }

    private var allItems: [FoundItem] {
        switch tool {
        case .large, .old, .downloads: return items
        case .duplicates, .similar: return groups.flatMap(\.items)
        case .analysis: return []
        }
    }

    // MARK: Work

    private func compute() {
        task?.cancel()
        if tool == .downloads {
            working = true; workLabel = "Reading Downloads…"; workProgress = 0
            task = Task {
                items = await Task.detached { ClutterService.downloads() }.value
                cataloged = true
                working = false
            }
            return
        }
        guard cataloged || tool != .downloads else { return }
        if !cataloged {
            // First press of "Start Scan" (or after changing folders): build the catalog, then compute.
            if cataloging { return }
            cataloging = true; catalogProgress = 0
            let folders = roots
            task = Task {
                let result = await Task.detached(priority: .utility) {
                    ClutterService.catalog(roots: folders) { n in Task { @MainActor in catalogProgress = n } }
                }.value
                if Task.isCancelled { cataloging = false; return }
                catalog = result
                cataloged = true
                cataloging = false
                compute()
            }
            return
        }
        let snapshot = catalog
        switch tool {
        case .large: items = ClutterService.largeFiles(snapshot)
        case .old: items = ClutterService.oldFiles(snapshot)
        case .analysis: breakdown = ClutterService.breakdown(snapshot)
        case .duplicates:
            working = true; workProgress = 0
            task = Task {
                groups = await Task.detached(priority: .utility) {
                    ClutterService.findDuplicates(snapshot) { label, p in
                        Task { @MainActor in workLabel = label; workProgress = p }
                    }
                }.value
                working = false
            }
        case .similar:
            working = true; workProgress = 0
            task = Task {
                groups = await Task.detached(priority: .utility) {
                    ClutterService.findSimilarImages(snapshot) { label, p in
                        Task { @MainActor in workLabel = label; workProgress = p }
                    }
                }.value
                working = false
            }
        case .downloads: break
        }
    }

    private func rebuildAfterRemoval(_ report: OperationReport) {
        // Drop anything that no longer exists, so the lists match the disk.
        let fm = FileManager.default
        catalog.removeAll { !fm.fileExists(atPath: $0.url.path) }
        items.removeAll { !fm.fileExists(atPath: $0.url.path) }
        groups = groups.compactMap { g in
            let remaining = g.items.filter { fm.fileExists(atPath: $0.url.path) }
            return remaining.count > 1 ? DuplicateGroup(items: remaining) : nil
        }
        breakdown = ClutterService.breakdown(catalog)
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Scan"
        panel.message = "Choose the folders Tegora should look through."
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            roots = panel.urls
            cataloged = false
            compute()
        }
    }
}
